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
  List.filter (fun el -> Web.DOM.Element.getAttribute "data-yuka-answer" el = Some key) elements

let ready el = Web.DOM.Element.getAttribute "data-pending" el = None

let first_ready answers =
  match List.find_opt ready answers with Some el -> of_json (Web.DOM.Node.textContent el) | None -> None

let full key elements = first_ready (mine key elements)

let ordered ?island key =
  let all selector = Array.to_list (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll selector Web.DOM.document)) in
  match island with
  | None -> mine key (all "script[data-yuka-answer]")
  | Some id -> (
      let elements = all "script[data-yuka-answer],script[data-yuka-props]" in
      let rec split before = function
        | [] -> None
        | el :: rest when Web.DOM.Element.getAttribute "data-yuka-props" el = Some id -> Some (before, mine key rest)
        | el :: rest -> split (if mine key [ el ] <> [] then el :: before else before) rest
      in
      match split [] elements with
      | None -> mine key elements
      | Some ((nearest :: _ as before), after) -> if ready nearest then before @ after else nearest :: after
      | Some ([], after) -> after)

let find ?island key =
  let answers = ordered ?island key in
  match first_ready answers with
  | Some r -> Found r
  | None when answers <> [] && Host.ready_state () = "loading" -> Pending
  | None -> Absent

let find_added key nodes =
  full key
    (List.concat_map
       (fun n ->
         (if Web.DOM.Element.localName n = "script" then [ n ] else [])
         @ Array.to_list (Web.DOM.NodeList.toArray (Web.DOM.Element.querySelectorAll "script[data-yuka-answer]" n)))
       (Array.to_list nodes))

let in_region region =
  List.filter_map
    (fun el ->
      match (Web.DOM.Element.getAttribute "data-yuka-answer" el, of_json (Web.DOM.Node.textContent el)) with
      | Some key, Some r -> Some (key, r)
      | _ -> None)
    (Array.to_list
       (Web.DOM.NodeList.toArray (Web.DOM.Element.querySelectorAll "script[data-yuka-answer]:not([data-pending])" region)))

let in_html html =
  let mark = "data-yuka-answer" in
  let n = String.length mark in
  let rec has i = i + n <= String.length html && (String.sub html i n = mark || has (i + 1)) in
  if not (has 0) then []
  else begin
    let parsed = Web.DOM.Document.createElement "div" Web.DOM.document in
    Web.DOM.Element.setInnerHTML parsed html;
    in_region parsed
  end

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
