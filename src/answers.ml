type found = Found of (Json.t, Status.error) result | Pending | Absent

let key name input = "r:" ^ name ^ " " ^ Json.to_string input

let error_codec : Status.error Codec.t =
  let open Status in
  let kind k extra : Json.t = `Assoc (("kind", `String k) :: extra) in
  let message m = [ ("message", `String m) ] in
  Codec.make
    ~encode:((function
      | Rejected m -> kind "rejected" (message m)
      | Forbidden -> kind "forbidden" []
      | Not_found -> kind "not_found" []
      | Server -> kind "server" []
      | Network m -> kind "network" (message m)
      | Protocol m -> kind "protocol" (message m)))
    ~decode:((fun j ->
        match j with
        | `Assoc fields -> (
            let text () =
              match List.assoc_opt "message" fields with Some (`String m) -> m | _ -> ""
            in
            match List.assoc_opt "kind" fields with
            | Some (`String "rejected") -> Ok (Rejected (text ()))
            | Some (`String "forbidden") -> Ok Forbidden
            | Some (`String "not_found") -> Ok Not_found
            | Some (`String "server") -> Ok Server
            | Some (`String "network") -> Ok (Network (text ()))
            | Some (`String "protocol") -> Ok (Protocol (text ()))
            | _ -> Json.mismatch "status error" j)
        | _ -> Json.mismatch "status error" j))

let to_json : (Json.t, Status.error) result -> Json.t = function
  | Ok j -> `Assoc [ ("ok", j) ]
  | Error e -> `Assoc [ ("error", Codec.encode error_codec e) ]

let of_json text =
  match Json.of_string text with
  | Ok (`Assoc [ ("ok", j) ]) -> Some (Ok j)
  | Ok (`Assoc [ ("error", e) ]) -> (
      match Codec.decode error_codec e with Ok e -> Some (Error e) | Error _ -> None)
  | _ -> None

let mine key elements =
  List.filter (fun el -> Host.get_attribute el "data-yuka-answer" = Some key) elements

let full key elements =
  match List.find_opt (fun el -> Host.get_attribute el "data-pending" = None) (mine key elements) with
  | Some el -> of_json (Host.text_content el)
  | None -> None

let find key =
  let elements = Array.to_list (Host.query_all (Host.document ()) "script[data-yuka-answer]") in
  match full key elements with
  | Some r -> Found r
  | None when mine key elements <> [] && Host.ready_state () = "loading" -> Pending
  | None -> Absent

let find_added key nodes =
  full key
    (List.concat_map
       (fun n ->
         (if Host.local_name n = "script" then [ n ] else [])
         @ Array.to_list (Host.query_all n "script[data-yuka-answer]"))
       (Array.to_list nodes))

let slot key =
  match !(Types.current_session ()) with
  | Some s when s.depth > 0 && not (List.mem key s.answered) ->
      s.answered <- key :: s.answered;
      Some s
  | _ -> None

let record key (result : (Json.t, Status.error) result option) settled =
  match (slot key, result) with
  | Some s, Some r -> s.answers <- (key, Some (to_json r)) :: s.answers
  | Some s, None when s.streaming ->
      s.answers <- (key, None) :: s.answers;
      s.pending <- Types.Pending_answer { key; answer = Async.map to_json settled } :: s.pending
  | _ -> ()

let record_value key value =
  match slot key with Some s -> s.answers <- (key, Some (to_json (value ()))) :: s.answers | None -> ()
