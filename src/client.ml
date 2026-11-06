include Island
open Types

type container = Web.node
type 'a promise = 'a Web.promise

let promise_map = Web.promise_map

let insert parent n = function
  | None -> Web.append_child parent n
  | Some before -> Web.insert_before parent n before

type ctx = {
  doc : Web.node;
}

type pos = {
  ctx : ctx;
  parent : Web.node;
  mutable cur : Web.node option;
  adopt : bool;
  svg : bool;
}

type 'a row = {
  key : string;
  mutable value : 'a;
  start : Web.node;
  stop : Web.node;
  mutable dispose : unit -> unit;
}

let svg_ns = "http://www.w3.org/2000/svg"

let on_dispose cleanup = Base.Effect.run ~cleanup (fun () -> ())

let non_bubbling =
  [ "focus"; "blur"; "mouseenter"; "mouseleave"; "load"; "error"; "scroll" ]

let handlers_key event = "__yuka_" ^ event

let skip pos n = pos.cur <- Web.next_sibling n

let take pos kind matches =
  match pos.cur with
  | Some n when pos.adopt && Web.node_type n = kind && matches n ->
      skip pos n;
      Some n
  | _ -> None

let comment_where pos matches data =
  match take pos 8 (fun n -> matches (Web.data n)) with
  | Some n -> n
  | None ->
      let n = Web.create_comment pos.ctx.doc data in
      insert pos.parent n pos.cur;
      n

let comment pos data = comment_where pos (String.equal data) data

let hole_start pos =
  comment_where pos (fun d -> String.length d > 0 && d.[0] = '[') "["

let walk_region pos visit =
  let rec go depth =
    match pos.cur with
    | None -> ()
    | Some n ->
        let d = if Web.node_type n = 8 then Web.data n else "" in
        let opens = String.length d > 0 && d.[0] = '[' in
        if d = "]" && depth = 0 then ()
        else begin
          skip pos n;
          visit n;
          go (if opens then depth + 1 else if d = "]" then depth - 1 else depth)
        end
  in
  go 0

let drop_to_end pos = if pos.adopt then walk_region pos Web.remove

let mount_slot pos slot =
  let dom = slot.dom in
  match take pos 8 (fun n -> Web.data n = "[$") with
  | Some _ ->
      let nodes = ref [] in
      walk_region pos (fun n -> nodes := Obj.repr n :: !nodes);
      dom := List.rev !nodes;
      ignore (comment pos "]")
  | None ->
      let start = Web.create_comment pos.ctx.doc "[$" in
      insert pos.parent start pos.cur;
      List.iter (fun n -> insert pos.parent (Obj.obj n) pos.cur) !dom;
      ignore (comment pos "]")

let text pos s =
  match if s = "" then None else take pos 3 (fun _ -> true) with
  | Some n ->
      if Web.data n <> s then Web.set_data n s;
      n
  | None ->
      let n = Web.create_text pos.ctx.doc s in
      insert pos.parent n pos.cur;
      n

let rec remove_between start stop =
  match Web.next_sibling start with
  | Some n when n != stop ->
      Web.remove n;
      remove_between start stop
  | _ -> ()

let remove_range start stop =
  remove_between start stop;
  Web.remove start;
  Web.remove stop

let move_range parent start stop anchor =
  let rec go n =
    let next = Web.next_sibling n in
    Web.insert_before parent n anchor;
    if n != stop then Option.iter go next
  in
  go start

let lis a =
  let n = Array.length a in
  let tails = Array.make n 0 in
  let prev = Array.make n (-1) in
  let len = ref 0 in
  for i = 0 to n - 1 do
    if a.(i) >= 0 then begin
      let lo = ref 0 and hi = ref !len in
      while !lo < !hi do
        let mid = (!lo + !hi) / 2 in
        if a.(tails.(mid)) < a.(i) then lo := mid + 1 else hi := mid
      done;
      if !lo > 0 then prev.(i) <- tails.(!lo - 1);
      tails.(!lo) <- i;
      if !lo = !len then incr len
    end
  done;
  let keep = Array.make n false in
  let k = ref (if !len > 0 then tails.(!len - 1) else -1) in
  while !k >= 0 do
    keep.(!k) <- true;
    k := prev.(!k)
  done;
  keep

let set_attr svg el name value =
  match name with
  | _ when svg -> (
      match value with
      | Some v -> Web.set_attribute el name v
      | None -> Web.remove_attribute el name)
  | "value" -> Web.set_string el "value" (Option.value value ~default:"")
  | "checked" | "selected" ->
      Web.set_bool el name
        (match value with None | Some "false" -> false | Some _ -> true)
  | _ -> (
      match value with
      | Some v -> Web.set_attribute el name v
      | None -> Web.remove_attribute el name)

let stopped_key = "__yuka_stopped"

type delegation = { mutable count : int; listener : Web.event -> unit }

let dispatch event ev =
  let key = handlers_key event in
  let rec go = function
    | None -> ()
    | Some n ->
        (match Web.get_prop n key with
        | Some hs -> List.iter (fun h -> h ev) hs
        | None -> ());
        if Web.get_flag ev stopped_key <> Some true then go (Web.parent_node n)
  in
  go (Some (Web.target ev))

let delegation_key event = "__yuka_delegation_" ^ event

let delegation ctx event =
  let key = delegation_key event in
  match Web.get_prop ctx.doc key with
  | Some (d : delegation) -> d
  | None ->
      let d = { count = 0; listener = dispatch event } in
      Web.set_prop ctx.doc key d;
      d

let add_handler ctx el event handler =
  if List.mem event non_bubbling then begin
    Web.add_listener el event handler;
    on_dispose (fun () -> Web.remove_listener el event handler)
  end
  else begin
    let d = delegation ctx event in
    d.count <- d.count + 1;
    if d.count = 1 then Web.add_listener ctx.doc event d.listener;
    let key = handlers_key event in
    let current = Option.value (Web.get_prop el key) ~default:[] in
    Web.set_prop el key (current @ [ handler ]);
    on_dispose (fun () ->
        let rest =
          List.filter
            (fun h -> h != handler)
            (Option.value (Web.get_prop el key) ~default:[])
        in
        Web.set_prop el key rest;
        d.count <- d.count - 1;
        if d.count = 0 then Web.remove_listener ctx.doc event d.listener)
  end

type compiled = { template : Web.node; paths : int array array }

let has_dynamic attrs =
  List.exists (function Static _ -> false | Dynamic _ | Handler _ -> true) attrs

let plan node =
  let ops = ref [] in
  let supported = ref true in
  let rec items path n last list = List.iter (item path n last) list
  and item path n last = function
    | Text "" -> supported := false
    | Text _ ->
        if !last then incr n;
        incr n;
        last := true
    | Fragment children -> items path n last children
    | Element { attrs; children; _ } ->
        let here = !n :: path in
        incr n;
        last := false;
        items here (ref 0) (ref false) children;
        if has_dynamic attrs then ops := here :: !ops
    | Hole _ | Await _ | Each _ ->
        ops := (!n :: path) :: !ops;
        n := !n + 2;
        last := false
    | Template { node; _ } -> item path n last node
    | Slot _ | Island _ -> supported := false
  in
  item [] (ref 0) (ref false) node;
  if !supported then
    Some (Array.of_list (List.rev_map (fun p -> Array.of_list (List.rev p)) !ops))
  else None

let compiled_template doc id node =
  let cache : (string, compiled option) Hashtbl.t =
    match Web.get_prop doc "__yuka_templates" with
    | Some c -> c
    | None ->
        let c = Hashtbl.create 16 in
        Web.set_prop doc "__yuka_templates" c;
        c
  in
  match Hashtbl.find_opt cache id with
  | Some c -> c
  | None ->
      let c =
        Option.map
          (fun paths ->
            let template = Web.create_element doc "template" in
            Web.set_inner_html template (Printer.skeleton_html node);
            { template; paths })
          (plan node)
      in
      Hashtbl.add cache id c;
      c

let rec mount_node pos last n =
  match n with
  | Text "" -> ignore (text pos "")
  | Text s ->
      if !last then ignore (comment pos "");
      ignore (text pos s);
      last := true
  | Fragment children -> List.iter (mount_node pos last) children
  | Element { tag; attrs; children } ->
      last := false;
      let svg = pos.svg || tag = "svg" in
      let adopted = take pos 1 (fun n -> Web.local_name n = tag) in
      let el =
        match adopted with
        | Some el -> el
        | None when svg -> Web.create_element_ns pos.ctx.doc svg_ns tag
        | None -> Web.create_element pos.ctx.doc tag
      in
      let inner_svg = svg && tag <> "foreignObject" in
      let inner =
        match adopted with
        | Some _ ->
            { pos with parent = el; cur = Web.first_child el; svg = inner_svg }
        | None -> { pos with parent = el; cur = None; adopt = false; svg = inner_svg }
      in
      let inner_last = ref false in
      List.iter (mount_node inner inner_last) children;
      List.iter (mount_attr pos.ctx svg el (Option.is_some adopted)) attrs;
      if Option.is_none adopted then insert pos.parent el pos.cur
  | Hole f ->
      last := false;
      mount_hole pos f
  | Await { async; loading; failed; render } ->
      last := false;
      let status = Async.watch async in
      mount_hole pos (fun () ->
          match Base.State.get status with
          | Async.Pending -> loading
          | Async.Done v -> render v
          | Async.Failed m -> failed m)
  | Slot slot ->
      last := false;
      mount_slot pos slot
  | Template { node; _ } when pos.adopt -> mount_node pos last node
  | Template { id; node } -> (
      last := false;
      match compiled_template pos.ctx.doc id node with
      | None -> mount_node pos last node
      | Some { template; paths } ->
          let clone = Web.import_node pos.ctx.doc (Web.content template) true in
          let count = Array.length paths in
          let parents = Array.make count clone in
          let targets = Array.make count clone in
          for k = 0 to count - 1 do
            let path = paths.(k) in
            let parent = ref clone and cur = ref clone in
            for d = 0 to Array.length path - 1 do
              parent := !cur;
              cur := Web.child_at !cur path.(d)
            done;
            parents.(k) <- !parent;
            targets.(k) <- !cur
          done;
          mount_planned pos.ctx pos.svg parents targets (ref 0) node;
          insert pos.parent clone pos.cur)
  | Island _ -> failwith "Yuka.Client: islands are not supported yet"
  | Each { items; key; equal; render } ->
      last := false;
      mount_each pos items key equal render

and mount_planned ctx svg parents targets next node =
  let take () =
    let i = !next in
    incr next;
    i
  in
  match node with
  | Text _ | Slot _ | Island _ -> ()
  | Fragment children ->
      List.iter (mount_planned ctx svg parents targets next) children
  | Template { node; _ } -> mount_planned ctx svg parents targets next node
  | Element { tag; attrs; children } ->
      let here = svg || tag = "svg" in
      let inner = here && tag <> "foreignObject" in
      List.iter (mount_planned ctx inner parents targets next) children;
      if has_dynamic attrs then begin
        let el = targets.(take ()) in
        List.iter (mount_attr ctx here el true) attrs
      end
  | Hole _ | Await _ | Each _ ->
      let i = take () in
      mount_node
        { ctx; parent = parents.(i); cur = Some targets.(i); adopt = true; svg }
        (ref false) node

and mount_attr ctx svg el adopted = function
  | Static (name, value) -> if not adopted then set_attr svg el name (Some value)
  | Dynamic (name, f) -> Base.Effect.run (fun () -> set_attr svg el name (f ()))
  | Handler (event, handler) -> add_handler ctx el event handler

and mount_hole pos f =
  let start = hole_start pos in
  let stop = ref None in
  let text_node = ref None in
  let place pos n =
    match n with
    | Text s ->
        text_node := Some (text pos s)
    | _ ->
        text_node := None;
        mount_node pos (ref false) n
  in
  Base.Effect.run (fun () ->
      let n = f () in
      match !stop with
      | None ->
          place pos n;
          drop_to_end pos
      | Some stop -> (
          match (n, !text_node) with
          | Text s, Some t -> if Web.data t <> s then Web.set_data t s
          | _ ->
              remove_between start stop;
              place { pos with cur = Some stop; adopt = false } n));
  stop := Some (comment pos "]")

and mount_each :
    type a.
    pos ->
    (unit -> a list) ->
    (a -> string) ->
    (a -> a -> bool) ->
    (a -> node) ->
    unit =
 fun pos items key equal render ->
  let start = comment pos "[" in
  ignore start;
  let source = Base.State.memo ~equal:(fun _ _ -> false) items in
  let make_entry pos k v =
    let start = comment pos "[" in
    let (), dispose =
      Base.mount (fun () ->
          Scheduler.untrack (fun () -> mount_node pos (ref false) (render v)))
    in
    { key = k; value = v; start; stop = comment pos "]"; dispose }
  in
  let entries =
    ref
      (Array.of_list
         (List.map (fun v -> make_entry pos (key v) v) (Base.State.peek source)))
  in
  let stop = comment pos "]" in
  let reconcile list =
    let items = Array.of_list list in
    let n = Array.length items in
    let keys = Array.map key items in
    let wanted = Hashtbl.create n in
    Array.iter
      (fun k ->
        if Hashtbl.mem wanted k then failwith ("Yuka.each: duplicate key " ^ k);
        Hashtbl.add wanted k ())
      keys;
    let old = Hashtbl.create 16 in
    Array.iteri
      (fun i e ->
        if Hashtbl.mem wanted e.key then Hashtbl.replace old e.key (i, e)
        else begin
          e.dispose ();
          remove_range e.start e.stop
        end)
      !entries;
    let keep =
      lis
        (Array.map
           (fun k ->
             match Hashtbl.find_opt old k with Some (i, _) -> i | None -> -1)
           keys)
    in
    let fresh anchor = { pos with cur = Some anchor; adopt = false } in
    let anchor = ref stop in
    let next = ref [] in
    for j = n - 1 downto 0 do
      let e =
        match Hashtbl.find_opt old keys.(j) with
        | Some (_, e) ->
            if not (equal e.value items.(j)) then begin
              e.dispose ();
              remove_between e.start e.stop;
              let (), dispose =
                Base.mount (fun () ->
                    Scheduler.untrack (fun () ->
                        mount_node (fresh e.stop) (ref false) (render items.(j))))
              in
              e.dispose <- dispose;
              e.value <- items.(j)
            end;
            if not keep.(j) then move_range pos.parent e.start e.stop !anchor;
            e
        | None -> make_entry (fresh !anchor) keys.(j) items.(j)
      in
      next := e :: !next;
      anchor := e.start
    done;
    entries := Array.of_list !next
  in
  Base.Effect.on_change
    ~equal:(fun _ _ -> false)
    source
    (fun ~prev:_ ~next -> reconcile next);
  on_dispose (fun () -> Array.iter (fun e -> e.dispose ()) !entries)

let platform_installed = ref false

let install_platform () =
  if not !platform_installed then begin
  platform_installed := true;
  Platform.platform :=
    {
      target_value = (fun e -> Web.value (Web.target e));
      target_checked = (fun e -> Web.checked (Web.target e));
      key = Web.key;
      meta_key = Web.meta_key;
      ctrl_key = Web.ctrl_key;
      prevent_default = Web.prevent_default;
      stop_propagation =
        (fun e ->
          Web.set_flag e stopped_key true;
          Web.stop_propagation e);
      target_tag = (fun e -> Web.local_name (Web.target e));
      shift_key = Web.shift_key;
      alt_key = Web.alt_key;
      navigate = Web.navigate;
      focus = Web.focus;
      scroll_into_view = Web.scroll_into_view;
      on_window =
        (fun name handler ->
          Web.add_listener (Web.window ()) name handler;
          fun () -> Web.remove_listener (Web.window ()) name handler);
    }
  end

let start ~adopt container f =
  install_platform ();
  let ctx =
    {
      doc = Web.owner_document container;
    }
  in
  let (), dispose =
    Base.mount (fun () ->
        let n = f () in
        if not adopt then Web.clear container "";
        mount_node
          { ctx; parent = container; cur = Web.first_child container; adopt; svg = false }
          (ref false) n)
  in
  dispose

let render container f = start ~adopt:false container f
let hydrate container f = start ~adopt:true container f

let cleanups : (int, unit -> unit) Hashtbl.t = Hashtbl.create 16
let live_islands : Web.node list ref = ref []
let next_cleanup = ref 0

let register cleanup =
  incr next_cleanup;
  Hashtbl.replace cleanups !next_cleanup cleanup;
  !next_cleanup

let transport name input =
  let result, resolve, fail = Async.make () in
  let failf fmt = Printf.ksprintf fail fmt in
  let id = register ignore in
  let finish () = Hashtbl.remove cleanups id in
  let abort =
    Web.fetch_post
    ("/_yuka/action/" ^ Web.encode_uri name)
    (Json.to_string input)
    (fun status body ->
      finish ();
      match Json.of_string body with
      | Ok (`Assoc fields) -> (
          match (List.assoc_opt "ok" fields, List.assoc_opt "error" fields) with
          | Some value, _ -> resolve value
          | None, Some (`String message) -> fail message
          | None, _ ->
              failf "action %s: unexpected response (HTTP %d)" name status)
      | Ok _ | Error _ ->
          failf "action %s: response is not JSON (HTTP %d)" name status)
    (fun cancelled message ->
      finish ();
      if cancelled then fail "cancelled"
      else failf "action %s: network error: %s" name message)
  in
  if Hashtbl.mem cleanups id then Hashtbl.replace cleanups id abort;
  result

let async_value id =
  let result, resolve, fail = Async.make () in
  let find () =
    let found =
      List.find_opt
        (fun s -> Web.get_attribute s "data-yuka-async" = Some id)
        (Array.to_list
           (Web.query_all (Web.document ()) "script[data-yuka-async]"))
    in
    match found with
    | None -> false
    | Some script when Web.text_content script = "" -> false
    | Some script when
        Web.ready_state () = "loading"
        && Result.is_error (Json.of_string (Web.text_content script)) ->
        false
    | Some script ->
        (match Json.of_string (Web.text_content script) with
        | Ok (`Assoc fields) -> (
            match (List.assoc_opt "ok" fields, List.assoc_opt "error" fields) with
            | Some value, _ -> resolve value
            | None, Some (`String message) -> fail message
            | None, _ -> fail ("async value " ^ id ^ ": unexpected shape"))
        | Ok _ -> fail ("async value " ^ id ^ ": unexpected shape")
        | Error message -> fail ("async value " ^ id ^ ": bad JSON: " ^ message));
        true
  in
  if not (find ()) then begin
    let cleanup_id = register ignore in
    let touches nodes =
      Array.exists
        (fun n ->
          let own = if Web.local_name n = "script" then [| n |] else [||] in
          Array.exists
            (fun s -> Web.get_attribute s "data-yuka-async" = Some id)
            (Array.append own (Web.query_all n "script[data-yuka-async]")))
        nodes
    in
    let disconnect =
      Web.watch_added (fun nodes ->
          touches nodes
          && find ()
          && (Hashtbl.remove cleanups cleanup_id;
              true))
    in
    Hashtbl.replace cleanups cleanup_id disconnect
  end;
  result

let started_key = "__yuka_started"

type lazy_entry = {
  lazy_name : string;
  load : unit -> Island.entry Web.promise;
  mutable loading : Island.entry Web.promise option;
}

let lazy_entry ~name load = { lazy_name = name; load; loading = None }

let boot entries props island =
  let id = Option.value (Web.get_attribute island "data-id") ~default:"" in
  let name = Option.value (Web.get_attribute island "data-name") ~default:"" in
  let fail reason =
    Web.console_error (Printf.sprintf "yuka island %s (%s): %s" id name reason);
    None
  in
  let entry = List.find_opt (fun e -> e.name = name) entries in
  match (entry, Hashtbl.find_opt props id) with
  | None, _ -> fail "unknown island name"
  | _, None -> fail "props script not found"
  | Some entry, Some text -> (
      match Json.of_string text with
      | Error message -> fail ("bad props JSON: " ^ message)
      | Ok json -> (
          match entry.decode json with
          | Error message -> fail ("cannot decode props: " ^ message)
          | Ok build -> (
              try
                Some (hydrate island build)
              with e -> fail (Printexc.to_string e))))

let schedule strategy island run =
  match strategy with
  | Some "idle" -> Web.on_idle run
  | Some "visible" -> (
      match Web.first_element_child island with
      | Some child when Web.has_intersection_observer island ->
          Web.on_visible child run
      | _ ->
          run ();
          ignore)
  | Some "interaction" ->
      let events = [ "pointerover"; "focusin"; "touchstart" ] in
      let fired = ref false in
      let rec listener ev =
        ignore ev;
        if not !fired then begin
          fired := true;
          List.iter (fun e -> Web.remove_listener island e listener) events;
          run ()
        end
      in
      List.iter (fun e -> Web.add_listener island e listener) events;
      fun () -> List.iter (fun e -> Web.remove_listener island e listener) events
  | _ ->
      run ();
      ignore

let stop () =
  let pending = Hashtbl.fold (fun _ f acc -> f :: acc) cleanups [] in
  Hashtbl.reset cleanups;
  List.iter (fun f -> f ()) pending;
  List.iter (fun island -> Web.set_bool island started_key false) !live_islands;
  live_islands := []

let load_lazy lazies name =
  match List.find_opt (fun l -> l.lazy_name = name) lazies with
  | None -> None
  | Some ({ loading = Some p; _ }) -> Some (p, ignore)
  | Some l ->
      let p = l.load () in
      l.loading <- Some p;
      Some (p, fun () -> l.loading <- None)

let start_island entries lazy_entries props island =
  Web.set_bool island started_key true;
  live_islands := island :: !live_islands;
  let id = register ignore in
  let fired = ref false in
  let name = Option.value (Web.get_attribute island "data-name") ~default:"" in
  let known = List.exists (fun e -> e.name = name) entries in
  let strategy = Web.get_attribute island "data-start" in
  let deferred =
    (not known)
    || (match strategy with
       | Some ("idle" | "visible" | "interaction") -> true
       | _ -> false)
  in
  let drop_events, replay_events =
    if deferred then Web.record_events island else (ignore, ignore)
  in
  let finish = function
    | Some dispose ->
        Hashtbl.replace cleanups id dispose;
        replay_events ()
    | None ->
        Hashtbl.remove cleanups id;
        drop_events ()
  in
  let run () =
    fired := true;
    match if known then None else load_lazy lazy_entries name with
    | None -> finish (boot entries props island)
    | Some (promise, forget) ->
        let cancelled = ref false in
        Hashtbl.replace cleanups id (fun () ->
            cancelled := true;
            drop_events ());
        let report reason =
          finish None;
          Web.console_error
            (Printf.sprintf "yuka island %s (%s): cannot load code: %s"
               (Option.value (Web.get_attribute island "data-id") ~default:"")
               name reason)
        in
        Web.promise_then
          (fun entry ->
            if not !cancelled then finish (boot [ entry ] props island))
          (fun message ->
            forget ();
            if not !cancelled then report message)
          promise
  in
  let cancel = schedule strategy island run in
  if not !fired then
    Hashtbl.replace cleanups id (fun () ->
        cancel ();
        drop_events ())

let script_props script =
  match Web.get_attribute script "data-yuka-props" with
  | Some id -> Some (id, Web.text_content script)
  | None -> None

let start ?(lazy_entries = []) entries =
  install_platform ();
  Action.transport := transport;
  Types.async_source := async_value;
  let props = Hashtbl.create 8 in
  let waiting = Hashtbl.create 8 in
  let island_id island =
    Option.value (Web.get_attribute island "data-id") ~default:""
  in
  let start_waiting ~final =
    let ready =
      Hashtbl.fold
        (fun id island acc ->
          if final || Hashtbl.mem props id then island :: acc else acc)
        waiting []
    in
    List.iter
      (fun island ->
        Hashtbl.remove waiting (island_id island);
        let started : bool option = Web.get_prop island started_key in
        if started <> Some true then
          start_island entries lazy_entries props island)
      ready
  in
  let note_island island =
    let started : bool option = Web.get_prop island started_key in
    if started <> Some true then Hashtbl.replace waiting (island_id island) island
  in
  let note_script ~final script =
    match script_props script with
    | Some (id, text) ->
        if final || Result.is_ok (Json.of_string text) then
          Hashtbl.replace props id text
    | None -> ()
  in
  let full ~final =
    let doc = Web.document () in
    Array.iter (note_script ~final) (Web.query_all doc "script[data-yuka-props]");
    Array.iter note_island (Web.query_all doc "yuka-island");
    start_waiting ~final
  in
  let parsed = Web.ready_state () <> "loading" in
  full ~final:parsed;
  if not parsed then begin
    let id = register ignore in
    let disconnect = ref ignore and remove_ready = ref ignore in
    let release () =
      !disconnect ();
      !remove_ready ();
      Hashtbl.remove cleanups id
    in
    disconnect :=
      Web.watch_added (fun nodes ->
          Array.iter
            (fun n ->
              if Web.local_name n = "yuka-island" then note_island n;
              if Web.local_name n = "script" then note_script ~final:false n;
              Array.iter note_island (Web.query_all n "yuka-island");
              Array.iter (note_script ~final:false)
                (Web.query_all n "script[data-yuka-props]"))
            nodes;
          start_waiting ~final:false;
          false);
    remove_ready :=
      Web.on_dom_ready (fun () ->
          full ~final:true;
          release ());
    Hashtbl.replace cleanups id release
  end

type registry = { entries : Island.entry list; lazy_registry : lazy_entry list }

let registry ?(lazy_entries = []) entries = { entries; lazy_registry = lazy_entries }
