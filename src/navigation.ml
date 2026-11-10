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

let load ~push ~restore url =
  if not !started then Web.location_assign url
  else begin
    cancel_pending ();
    let controller = Web.new_controller () in
    pending := Some controller;
    Web.fetch_page url controller
      (fun final text ->
        pending := None;
        Client.stop ();
        Web.swap_page text;
        if push then begin
          let key = Web.fresh_key () in
          Web.history_push_key key final;
          current_key := key
        end;
        loaded := Web.current_url ();
        (match restore with
        | Some y -> Web.scroll_to y
        | None -> Web.scroll_to_hash (hash_of final));
        !start_islands ())
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
