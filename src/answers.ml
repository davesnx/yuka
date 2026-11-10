type found = Found of (Json.t, Status.error) result | Pending | Absent

let key name input = "r:" ^ name ^ " " ^ Json.to_string input

let to_json : (Json.t, Status.error) result -> Json.t = function
  | Ok j -> `Assoc [ ("ok", j) ]
  | Error e -> `Assoc [ ("error", Status.error_codec.encode e) ]

let of_json text =
  match Json.of_string text with
  | Ok (`Assoc [ ("ok", j) ]) -> Some (Ok j)
  | Ok (`Assoc [ ("error", e) ]) -> (
      match Status.error_codec.decode e with Ok e -> Some (Error e) | Error _ -> None)
  | _ -> None

let mine key elements =
  List.filter (fun el -> Web.get_attribute el "data-yuka-answer" = Some key) elements

let full key elements =
  match List.find_opt (fun el -> Web.get_attribute el "data-pending" = None) (mine key elements) with
  | Some el -> of_json (Web.text_content el)
  | None -> None

let find key =
  let elements = Array.to_list (Web.query_all (Web.document ()) "script[data-yuka-answer]") in
  match full key elements with
  | Some r -> Found r
  | None when mine key elements <> [] && Web.ready_state () = "loading" -> Pending
  | None -> Absent

let find_added key nodes =
  full key
    (List.concat_map
       (fun n ->
         (if Web.local_name n = "script" then [ n ] else [])
         @ Array.to_list (Web.query_all n "script[data-yuka-answer]"))
       (Array.to_list nodes))

let slot key =
  match !Types.current_session with
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
