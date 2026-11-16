type entry = {
  id : string;
  name : string;
  mutable text : string;
  mutable change : (Json.t -> unit) option;
  mutable drops : (unit -> unit) list;
}

let page : entry Web.table option ref = ref None
let seen = "__yuka_seen"
let selector = "script[data-yuka-context]"

let drop t e =
  Web.table_delete t e.id;
  Array.iter
    (fun s -> if Option.equal String.equal (Web.get_attribute s "data-yuka-context") (Some e.id) then Web.set_bool s seen false)
    (Web.query_all (Web.document ()) selector);
  List.iter (fun f -> f ()) e.drops

let put t id name text =
  match Web.table_get t id with
  | Some e when String.equal e.name name ->
      if not (String.equal e.text text) then begin
        e.text <- text;
        match (e.change, Json.of_string text) with
        | Some f, Ok j -> f j
        | _ ->
            List.iter (fun f -> f ()) e.drops;
            e.drops <- []
      end
  | old ->
      Option.iter (drop t) old;
      Web.table_set t id { id; name; text; change = None; drops = [] }

let table () =
  match !page with
  | Some t -> t
  | None ->
      let t = Web.table () in
      page := Some t;
      t

let scan root =
  let t = table () in
  Array.iter
    (fun s ->
      let text = Web.text_content s in
      if
        (match Web.get_prop s seen with Some true -> false | _ -> true)
        && (Web.ready_state () <> "loading" || Result.is_ok (Json.of_string text))
      then begin
        Web.set_bool s seen true;
        put t
          (Option.value (Web.get_attribute s "data-yuka-context") ~default:"")
          (Option.value (Web.get_attribute s "data-name") ~default:"")
          text
      end)
    (Web.query_all root selector);
  t

let set id name json = Scheduler.batch (fun () -> put (scan (Web.document ())) id name (Json.to_string json))

let clear () =
  Option.iter (fun t -> Array.iter (drop t) (Web.table_values t)) !page;
  page := None

let listed doc =
  Array.fold_left
    (fun acc island ->
      match Web.get_attribute island "data-ctx" with
      | Some ctx ->
          List.filter_map
            (fun pair -> match String.index_opt pair '=' with Some i -> Some (String.sub pair (i + 1) (String.length pair - i - 1)) | None -> None)
            (String.split_on_char ' ' ctx)
          @ acc
      | None -> acc)
    [] (Web.query_all doc "yuka-island")

let swapped = function
  | None -> ()
  | Some region ->
      let doc = Web.document () in
      let fresh = Web.query_all region selector in
      Array.iter
        (fun old ->
          if
            (not (Web.contains region old))
            && Array.exists
                 (fun s ->
                   Option.equal String.equal (Web.get_attribute s "data-yuka-context")
                     (Web.get_attribute old "data-yuka-context"))
                 fresh
          then Web.remove old)
        (Web.query_all doc selector);
      Option.iter
        (fun t ->
          Scheduler.batch (fun () -> ignore (scan region));
          let ids = listed doc in
          Array.iter (fun e -> if not (List.exists (String.equal e.id) ids) then drop t e) (Web.table_values t))
        !page

let id_in scope name =
  List.find_map
    (fun pair ->
      match String.index_opt pair '=' with
      | Some i when String.equal (String.sub pair 0 i) name -> Some (String.sub pair (i + 1) (String.length pair - i - 1))
      | _ -> None)
    (String.split_on_char ' ' scope)

let reader name (codec : 'a Codec.t) =
  Platform.swapped := swapped;
  Platform.cleared := clear;
  let cache : 'a Web.table option ref = ref None in
  fun scope ->
    match id_in scope name with
    | None -> None
    | Some id -> (
        let values = match !cache with Some c -> c | None -> let c = Web.table () in cache := Some c; c in
        match Web.table_get values id with
        | Some v -> Some v
        | None -> (
            let t = match !page with Some t when Web.table_has t id -> t | _ -> scan (Web.document ()) in
            match Web.table_get t id with
            | None -> None
            | Some e -> (
                let fail m =
                  Web.console_error ("yuka: context " ^ name ^ " (" ^ id ^ "): " ^ m);
                  None
                in
                match Json.of_string e.text with
                | Error m -> fail m
                | Ok j -> (
                    Types.state_target := (fun f -> e.change <- Some f);
                    let r = match Codec.decode codec j with r -> r | exception x -> Error (Web.exn_to_string x) in
                    Types.state_target := ignore;
                    match r with
                    | Error m -> fail m
                    | Ok v ->
                        Web.table_set values id v;
                        e.drops <- (fun () -> Web.table_delete values id) :: e.drops;
                        Some v))))
