type entry = {
  id : string;
  name : string;
  mutable text : string;
  mutable change : (Json.t -> unit) option;
  mutable drops : (unit -> unit) list;
}

let page : entry Host.table option ref = ref None
let seen = "__yuka_seen"
let selector = "script[data-yuka-context]"

let drop t e =
  Host.table_delete t e.id;
  Array.iter
    (fun s -> if Option.equal String.equal (Web.DOM.Element.getAttribute "data-yuka-context" s) (Some e.id) then Host.set_bool s seen false)
    (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll selector Web.DOM.document));
  List.iter (fun f -> f ()) e.drops

let put t id name text =
  match Host.table_get t id with
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
      Host.table_set t id { id; name; text; change = None; drops = [] }

let table () =
  match !page with
  | Some t -> t
  | None ->
      let t = Host.table () in
      page := Some t;
      t

let scan root =
  let t = table () in
  Array.iter
    (fun s ->
      let text = Web.DOM.Node.textContent s in
      if
        (match Host.get_prop s seen with Some true -> false | _ -> true)
        && (Host.ready_state () <> "loading" || Result.is_ok (Json.of_string text))
      then begin
        Host.set_bool s seen true;
        put t
          (Option.value (Web.DOM.Element.getAttribute "data-yuka-context" s) ~default:"")
          (Option.value (Web.DOM.Element.getAttribute "data-name" s) ~default:"")
          text
      end)
    (Web.DOM.NodeList.toArray (Web.DOM.Element.querySelectorAll selector root));
  t

let set id name json = Scheduler.batch (fun () -> put (scan (Web.DOM.Document.documentElement Web.DOM.document)) id name (Json.to_string json))

let clear () =
  Option.iter (fun t -> Array.iter (drop t) (Host.table_values t)) !page;
  page := None

let listed doc =
  Array.fold_left
    (fun acc island ->
      match (Web.DOM.Element.getAttribute "data-ctx" island) with
      | Some ctx ->
          List.filter_map
            (fun pair -> match String.index_opt pair '=' with Some i -> Some (String.sub pair (i + 1) (String.length pair - i - 1)) | None -> None)
            (String.split_on_char ' ' ctx)
          @ acc
      | None -> acc)
    [] (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll "yuka-island" doc))

let swapped = function
  | None -> ()
  | Some region ->
      let doc = Web.DOM.document in
      let fresh = Web.DOM.NodeList.toArray (Web.DOM.Element.querySelectorAll selector region) in
      Array.iter
        (fun old ->
          if
            (not (Web.DOM.Node.contains old region))
            && Array.exists
                 (fun s ->
                   Option.equal String.equal (Web.DOM.Element.getAttribute "data-yuka-context" s)
                     (Web.DOM.Element.getAttribute "data-yuka-context" old))
                 fresh
          then Web.DOM.Element.remove old)
        (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll selector doc));
      Option.iter
        (fun t ->
          Scheduler.batch (fun () -> ignore (scan region));
          let ids = listed doc in
          Array.iter (fun e -> if not (List.exists (String.equal e.id) ids) then drop t e) (Host.table_values t))
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
  let cache : 'a Host.table option ref = ref None in
  fun scope ->
    match id_in scope name with
    | None -> None
    | Some id -> (
        let values = match !cache with Some c -> c | None -> let c = Host.table () in cache := Some c; c in
        match Host.table_get values id with
        | Some v -> Some v
        | None -> (
            let t = match !page with Some t when Host.table_has t id -> t | _ -> scan (Web.DOM.Document.documentElement Web.DOM.document) in
            match Host.table_get t id with
            | None -> None
            | Some e -> (
                let fail m =
                  Host.console_error ("yuka: context " ^ name ^ " (" ^ id ^ "): " ^ m);
                  None
                in
                match Json.of_string e.text with
                | Error m -> fail m
                | Ok j -> (
                    Types.state_target := (fun f -> e.change <- Some f);
                    let r = match Codec.decode codec j with r -> r | exception x -> Error (Host.exn_to_string x) in
                    Types.state_target := ignore;
                    match r with
                    | Error m -> fail m
                    | Ok v ->
                        Host.table_set values id v;
                        e.drops <- (fun () -> Host.table_delete values id) :: e.drops;
                        Some v))))
