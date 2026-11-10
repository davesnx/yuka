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

let find key =
  let mine =
    List.filter
      (fun el -> Web.get_attribute el "data-yuka-answer" = Some key)
      (Array.to_list (Web.query_all (Web.document ()) "script[data-yuka-answer]"))
  in
  let full = List.find_opt (fun el -> Web.get_attribute el "data-pending" = None) mine in
  match full with
  | Some el -> ( match of_json (Web.text_content el) with Some r -> Found r | None -> Absent)
  | None when mine <> [] && Web.ready_state () = "loading" -> Pending
  | None -> Absent

let record key (result : (Json.t, Status.error) result option) settled =
  match !Types.current_session with
  | Some s when s.depth > 0 && not (List.mem key s.answered) -> (
      s.answered <- key :: s.answered;
      match result with
      | Some r -> s.answers <- Printer.answer_script key (to_json r) :: s.answers
      | None when s.streaming ->
          s.answers <- Printer.pending_answer_script key :: s.answers;
          s.pending <- Types.Pending_answer { key; answer = Async.map to_json settled } :: s.pending
      | None -> ())
  | _ -> ()
