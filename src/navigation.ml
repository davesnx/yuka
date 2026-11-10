let started = ref false
let listening : Web.node option ref = ref None
let pending : Web.controller option ref = ref None
let scroll_table : float Web.table option ref = ref None

let scrolls () =
  match !scroll_table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      scroll_table := Some t;
      t

let current_key = ref ""
let loaded = ref ""
let start_islands : (unit -> unit) ref = ref (fun () -> ())

let cancel_pending () =
  match !pending with
  | Some c ->
      pending := None;
      Web.abort c
  | None -> ()

let save_scroll () = Web.table_set (scrolls ()) !current_key (Web.scroll_y ())

let hash_of url =
  match String.index_opt url '#' with
  | Some i -> String.sub url i (String.length url - i)
  | None -> ""

let outlets () = Web.query_all (Web.document ()) "yuka-outlet"

let keys () =
  match List.filter_map (fun o -> Web.get_attribute o "data-k") (Array.to_list (outlets ())) with
  | [] -> "-"
  | keys -> String.concat " " keys

let build () =
  match Web.query_all (Web.document ()) "meta[name=yuka-build]" with
  | [| meta |] -> Web.get_attribute meta "content"
  | _ -> None

let mark_links outlet path =
  let doc = Web.document () in
  let islands = Web.query_all doc "yuka-island" in
  Array.iter
    (fun a ->
      if not (Web.contains outlet a || Array.exists (fun i -> Web.contains i a) islands) then
        match (Web.get_attribute a "href" = Some path, Web.get_attribute a "aria-current") with
        | true, None -> Web.set_attribute a "aria-current" "page"
        | false, Some "page" -> Web.remove_attribute a "aria-current"
        | _ -> ())
    (Web.query_all doc "a")

let swap final header text =
  let outlet =
    Option.map
      (fun key -> Array.find_opt (fun o -> Web.get_attribute o "data-k" = Some key) (outlets ()))
      (header "yuka-outlet")
  in
  match outlet with
  | Some None -> false
  | Some (Some el) ->
      let title =
        Option.map (fun t -> try Web.decode_uri t with _ -> t) (header "yuka-title")
      in
      Client.stop_within el;
      Web.set_inner_html el text;
      Option.iter Web.set_title title;
      mark_links el (fst (Router.split_target final));
      true
  | None ->
      Client.stop ();
      Web.swap_page text;
      true

let html header =
  match header "content-type" with
  | Some t -> String.starts_with ~prefix:"text/html" (String.lowercase_ascii t)
  | None -> false

let load ~push ~restore url =
  if not !started then Web.location_assign url
  else begin
    cancel_pending ();
    let controller = Web.new_controller () in
    pending := Some controller;
    Web.fetch_page url (keys ()) controller
      (fun final status header text ->
        pending := None;
        let stale = match header "yuka-build" with Some b -> build () <> Some b | None -> false in
        let shown = (status >= 200 && status < 300) || status >= 400 in
        if stale || (not shown) || (not (html header)) || not (swap final header text) then
          Web.location_assign final
        else begin
          if push then begin
            let key = Web.fresh_key () in
            Web.history_push_key key final;
            current_key := key
          end;
          loaded := Web.current_url ();
          (match restore with
          | Some y -> Web.scroll_to y
          | None -> Web.scroll_to_hash (hash_of final));
          !start_islands ()
        end)
      (fun () ->
        pending := None;
        Web.location_assign url)
  end

let navigate url =
  save_scroll ();
  load ~push:true ~restore:None url

let on_click e =
  match Web.click_href e with
  | "" -> ()
  | href ->
      Web.prevent_default e;
      navigate href

let on_popstate _ =
  save_scroll ();
  current_key := Web.history_key ();
  let y = Option.value (Web.table_get (scrolls ()) !current_key) ~default:0. in
  if Web.current_url () = !loaded then begin
    cancel_pending ();
    Web.scroll_to y
  end
  else load ~push:false ~restore:(Some y) (Web.current_url ())

let start ?lazy_entries entries =
  cancel_pending ();
  started := true;
  Web.manual_scroll ();
  current_key := Web.history_key ();
  if !current_key = "" then begin
    current_key := Web.fresh_key ();
    Web.history_replace_key !current_key
  end;
  loaded := Web.current_url ();
  let doc = Web.document () in
  (match !listening with
  | Some d when d == doc -> ()
  | _ ->
      listening := Some doc;
      Web.add_listener doc "click" on_click;
      Web.add_listener (Web.window ()) "popstate" on_popstate);
  (start_islands :=
     fun () ->
       Client.start ?lazy_entries entries;
       Platform.platform := { !Platform.platform with navigate });
  !start_islands ()

let stop () =
  cancel_pending ();
  started := false;
  (match !listening with
  | Some doc ->
      listening := None;
      Web.remove_listener doc "click" on_click;
      Web.remove_listener (Web.window ()) "popstate" on_popstate
  | None -> ());
  start_islands := (fun () -> ());
  if !Platform.platform.navigate == navigate then
    Platform.platform := { !Platform.platform with navigate = Web.navigate };
  Client.stop ()
