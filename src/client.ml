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
  mutable first : Web.node;
  mutable last : Web.node;
  mutable dispose : unit -> unit;
}

let svg_ns = "http://www.w3.org/2000/svg"

let on_dispose = Base.own

let non_bubbling = function
  | "focus" | "blur" | "mouseenter" | "mouseleave" | "load" | "error" | "scroll" ->
      true
  | _ -> false

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
      if Dev.on then if pos.adopt then
        Dev.mismatch pos.parent ("<!--" ^ data ^ "-->") pos.cur;
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

let drop_to_end pos =
  if Dev.on then if pos.adopt then
    walk_region { pos with cur = pos.cur } (fun n ->
        Dev.mismatch pos.parent "nothing" (Some n));
  if pos.adopt then walk_region pos Web.remove

let mount_slot pos slot =
  let dom = slot.dom in
  match take pos 8 (fun n -> Web.data n = "[$") with
  | Some _ ->
      let nodes = ref [] in
      walk_region pos (fun n -> nodes := Obj.repr n :: !nodes);
      dom := List.rev !nodes;
      ignore (comment pos "]")
  | None ->
      if Dev.on then if pos.adopt then
        Dev.mismatch pos.parent "<!--[$-->" pos.cur;
      let start = Web.create_comment pos.ctx.doc "[$" in
      insert pos.parent start pos.cur;
      List.iter (fun n -> insert pos.parent (Obj.obj n) pos.cur) !dom;
      ignore (comment pos "]")

let text pos s =
  match if s = "" then None else take pos 3 (fun _ -> true) with
  | Some n ->
      if Web.data n <> s then begin
        if Dev.on then Dev.mismatch pos.parent ("\"" ^ s ^ "\"") (Some n);
        Web.set_data n s
      end;
      n
  | None ->
      if Dev.on then if pos.adopt && s <> "" then
        Dev.mismatch pos.parent ("\"" ^ s ^ "\"") pos.cur;
      let n = Web.create_text pos.ctx.doc s in
      insert pos.parent n pos.cur;
      n

let rec remove_between start stop =
  match Web.next_sibling start with
  | Some n when n != stop ->
      Web.remove n;
      remove_between start stop
  | _ -> ()

let remove_range first last =
  if first != last then remove_between first last;
  Web.remove first;
  if first != last then Web.remove last

let move_range parent first last anchor =
  let rec go n =
    let next = Web.next_sibling n in
    insert parent n anchor;
    if n != last then Option.iter go next
  in
  go first

let before pos =
  match pos.cur with
  | Some n -> Option.get (Web.previous_sibling n)
  | None -> Option.get (Web.last_child pos.parent)

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

let stopped_key = Platform.stopped_key

type handler = { run : Web.event -> unit; owner : Base.owner; gen : int }

let live h = h.owner.gen = h.gen
let acting : Base.owner option ref = ref None

let acting_as owner f ev =
  let prev = !acting in
  acting := owner;
  match f ev with
  | () -> acting := prev
  | exception e ->
      acting := prev;
      raise e

let dispatch event ev =
  let key = handlers_key event in
  let rec go = function
    | None -> ()
    | Some n ->
        (match Web.get_prop n key with
        | Some hs ->
            List.iter
              (fun h ->
                if live h then
                  try acting_as (Some h.owner) h.run ev
                  with e ->
                    Base.fail h.owner e;
                    Web.set_flag ev stopped_key true)
              hs
        | None -> ());
        match Web.get_flag ev stopped_key with
        | Some true -> ()
        | Some false | None -> go (Web.parent_node n)
  in
  go (Some (Web.target ev))

let delegated : (Web.node * string * string) list ref = ref []

let delegate ctx event =
  match List.find_opt (fun (d, e, _) -> d == ctx.doc && e = event) !delegated with
  | Some (_, _, key) -> key
  | None ->
      let mark = "__yuka_delegation_" ^ event in
      (match Web.get_prop ctx.doc mark with
      | Some (_ : bool) -> ()
      | None ->
          Web.set_prop ctx.doc mark true;
          Web.add_listener ctx.doc event (dispatch event));
      let key = handlers_key event in
      delegated := (ctx.doc, event, key) :: !delegated;
      key

let unowned : Base.owner = { last = None; gen = 0; catch = None }

let add_handler ctx el event handler =
  let owner = Option.value !Base.current_owner ~default:unowned in
  if non_bubbling event then begin
    let handler = acting_as !Base.current_owner handler in
    let handler ev = try handler ev with e -> Base.fail owner e in
    Web.add_listener el event handler;
    on_dispose (fun () -> Web.remove_listener el event handler)
  end
  else begin
    let key = delegate ctx event in
    let h = { run = handler; owner; gen = owner.gen } in
    match Web.get_prop el key with
    | None -> Web.set_prop el key [ h ]
    | Some hs -> Web.set_prop el key (List.rev_append (List.rev (List.filter live hs)) [ h ])
  end

type compiled = { root : Web.node; kid_svg : int; attr_svg : int }

type Types.cache += Compiled of Web.node * compiled option

let rec same_tree shape n =
  match shape with
  | Fixed_element { tag; attrs; children } ->
      Web.node_type n = 1
      && Web.local_name n = tag
      && (Template_build.void_or_value tag attrs || same_children children (Web.first_child n))
  | Fixed_text _ | Part _ -> false

and same_children children cur =
  let rec go after_text cur = function
    | [] -> Option.is_none cur
    | (Part _ | Fixed_text "") :: rest -> go after_text cur rest
    | Fixed_text t :: rest -> (
        let cur =
          if not after_text then cur
          else
            match cur with
            | Some c when Web.node_type c = 8 -> Web.next_sibling c
            | _ -> None
        in
        match cur with
        | Some c when Web.node_type c = 3 && Web.data c = t ->
            go true (Web.next_sibling c) rest
        | _ -> false)
    | (Fixed_element _ as e) :: rest -> (
        match cur with
        | Some c when same_tree e c -> go false (Web.next_sibling c) rest
        | _ -> false)
  in
  go false cur children

let compile doc svg (template : template) =
  let t = Web.create_element doc "template" in
  Web.set_inner_html t
    (if svg then "<svg>" ^ template.markup ^ "</svg>" else template.markup);
  let only n =
    match n with
    | Some n when Option.is_none (Web.next_sibling n) -> Some n
    | _ -> None
  in
  let parsed =
    match only (Web.first_child (Web.content t)) with
    | Some top when svg -> only (Web.first_child top)
    | top -> top
  in
  match parsed with
  | Some n when same_tree template.shape n ->
      Some
        {
          root = Web.import_node doc n true;
          kid_svg =
            (if svg then Template_build.kid_svg_in_svg else Template_build.kid_svg_in_html);
          attr_svg =
            (if svg then Template_build.attr_svg_in_svg
             else Template_build.attr_svg_in_html);
        }
  | _ -> None

let compiled doc svg (template : template) =
  match if svg then template.in_svg else template.in_html with
  | Compiled (d, c) when d == doc -> c
  | _ ->
      let c = compile doc svg template in
      if svg then template.in_svg <- Compiled (doc, c)
      else template.in_html <- Compiled (doc, c);
      c

let fixed_root template =
  match template.shape with Fixed_element _ -> true | Fixed_text _ | Part _ -> false

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
      if Dev.on then if pos.adopt && Option.is_none adopted then
        Dev.mismatch pos.parent ("<" ^ tag ^ ">") pos.cur;
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
      mount_children inner children;
      if Dev.on then if Option.is_some adopted && tag <> "textarea" then
        walk_region inner (fun n -> Dev.mismatch el "nothing" (Some n));
      List.iter (mount_attr pos.ctx svg el (Option.is_some adopted)) attrs;
      if Option.is_none adopted then insert pos.parent el pos.cur
  | Hole f ->
      last := false;
      mount_hole pos false f
  | Await { async; loading; failed; render } ->
      last := false;
      let status = Async.watch async in
      mount_hole pos false (fun () ->
          match State.get status with
          | Async.Pending -> loading
          | Async.Done v -> render v
          | Async.Failed m -> failed m)
  | Slot slot ->
      last := false;
      mount_slot pos slot
  | Template { template; parts } when pos.adopt || not (fixed_root template) ->
      mount_node pos last (Template.expand template parts)
  | Template { template; parts } -> (
      match compiled pos.ctx.doc pos.svg template with
      | Some c ->
          last := false;
          instantiate pos template c parts
      | None -> mount_node pos last (Template.expand template parts))
  | Island _ -> failwith "Yuka.Client: islands are not supported yet"
  | Catch { client; _ } ->
      mount_node pos last (client (if pos.adopt then Option.map Obj.repr pos.cur else None))
  | Each { items; key; equal; render } ->
      last := false;
      mount_each pos false items key equal render

and mount_children pos = function
  | [ Hole f ] -> mount_hole pos true f
  | [ Each { items; key; equal; render } ] -> mount_each pos true items key equal render
  | children ->
      let last = ref false in
      List.iter (mount_node pos last) children

and instantiate pos (template : template) c parts =
  let doc = pos.ctx.doc in
  let { Template_build.walk; kids; attrs; values } = template.plan in
  let root = Web.clone_node c.root true in
  let nodes = Web.walk root walk in
  let last = ref false in
  let get = Array.unsafe_get in
  let k = ref 0 in
  while !k < Array.length kids do
    let i = !k in
    k := i + 5;
    match parts.(get kids i) with
    | Child n -> (
        let anchor = get kids (i + 2) and flags = get kids (i + 3) in
        let anchor = if anchor < 0 then None else Some (get nodes anchor) in
        let inner =
          { ctx = pos.ctx; parent = get nodes (get kids (i + 1)); cur = anchor;
            adopt = false; svg = flags land c.kid_svg <> 0 }
        in
        if flags land Template_build.kid_only <> 0 then mount_children inner [ n ]
        else begin
          if flags land Template_build.kid_first_of_run <> 0 then
            last := flags land Template_build.kid_text_before <> 0;
          mount_node inner last n;
          match (get kids (i + 4), anchor) with
          | 1, Some sep -> if not !last then Web.remove sep
          | 2, Some next ->
              if !last then Web.insert_before inner.parent (Web.create_comment doc "") next
          | _ -> ()
        end)
    | Attribute _ | No_attribute -> ()
  done;
  Array.iter (fun (i, v) -> set_attr false (get nodes i) "value" (Some v)) values;
  let k = ref 0 in
  while !k < Array.length attrs do
    let i = !k in
    k := i + 3;
    match parts.(get attrs (i + 1)) with
    | Attribute a ->
        mount_attr pos.ctx (get attrs (i + 2) land c.attr_svg <> 0) (get nodes (get attrs i)) false a
    | Child _ | No_attribute -> ()
  done;
  insert pos.parent root pos.cur

and mount_attr ctx svg el adopted = function
  | Static (name, value) -> if not adopted then set_attr svg el name (Some value)
  | Dynamic (name, f) -> Base.Effect.run (fun () -> set_attr svg el name (f ()))
  | Handler (event, handler) -> add_handler ctx el event handler

and mount_hole pos owned f =
  let start = if owned then None else Some (hole_start pos) in
  let stop = ref None in
  let mounted = ref false in
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
      if not !mounted then begin
        mounted := true;
        let close () =
          drop_to_end pos;
          if not owned then stop := Some (comment pos "]")
        in
        (try place pos n
         with e ->
           close ();
           raise e);
        close ()
      end
      else
        match (n, !text_node) with
        | Text s, Some t -> if Web.data t <> s then Web.set_data t s
        | _ -> (
            match start with
            | None ->
                Web.clear pos.parent "";
                place { pos with cur = None; adopt = false } n
            | Some start ->
                remove_between start (Option.get !stop);
                place { pos with cur = !stop; adopt = false } n))

and mount_each :
    type a.
    pos ->
    bool ->
    (unit -> a list) ->
    (a -> string) ->
    (a -> a -> bool) ->
    (a -> node) ->
    unit =
 fun pos owned items key equal render ->
  let start = if owned then None else Some (comment pos "[") in
  let source = State.memo ~equal:(fun _ _ -> false) items in
  let mount_row pos v =
    let first = ref pos.parent and last = ref pos.parent in
    let (), dispose =
      Base.mount (fun () ->
          Scheduler.untrack (fun () ->
              let n = render v in
              if Template.single_element n then begin
                mount_node pos (ref false) n;
                first := before pos;
                last := !first
              end
              else begin
                first := comment pos "[";
                mount_node pos (ref false) n;
                last := comment pos "]"
              end))
    in
    (!first, !last, dispose)
  in
  let make_entry pos k v =
    let first, last, dispose = mount_row pos v in
    { key = k; value = v; first; last; dispose }
  in
  let entries =
    ref
      (Array.of_list
         (List.map (fun v -> make_entry pos (key v) v) (State.peek source)))
  in
  let stop = if owned then (drop_to_end pos; None) else Some (comment pos "]") in
  let clear_all () =
    match start with
    | None -> Web.clear pos.parent ""
    | Some start -> Web.delete_between pos.parent start (Option.get stop)
  in
  let reconcile list =
    let items = Array.of_list list in
    let n = Array.length items in
    let keys = Array.map key items in
    let wanted = Web.table () in
    Array.iter
      (fun k ->
        if Web.table_has wanted k then failwith ("Yuka.each: duplicate key " ^ k);
        Web.table_set wanted k true)
      keys;
    let old = Web.table () in
    let removed = ref [] in
    Array.iteri
      (fun i e ->
        if Web.table_has wanted e.key then Web.table_set old e.key (i, e)
        else removed := e :: !removed)
      !entries;
    if Web.table_size old = 0 && Array.length !entries > 0 then begin
      Array.iter (fun e -> e.dispose ()) !entries;
      clear_all ()
    end
    else
      List.iter
        (fun e ->
          e.dispose ();
          remove_range e.first e.last)
        (List.rev !removed);
    let keep =
      lis
        (Array.map
           (fun k ->
             match Web.table_get old k with Some (i, _) -> i | None -> -1)
           keys)
    in
    let fresh anchor = { pos with cur = anchor; adopt = false } in
    let anchor = ref stop in
    let next = ref [] in
    for j = n - 1 downto 0 do
      let e =
        match Web.table_get old keys.(j) with
        | Some (_, e) ->
            if not (equal e.value items.(j)) then begin
              e.dispose ();
              let first, last, dispose = mount_row (fresh (Some e.first)) items.(j) in
              remove_range e.first e.last;
              e.first <- first;
              e.last <- last;
              e.dispose <- dispose;
              e.value <- items.(j)
            end;
            if not keep.(j) then move_range pos.parent e.first e.last !anchor;
            e
        | None -> make_entry (fresh !anchor) keys.(j) items.(j)
      in
      next := e :: !next;
      anchor := Some e.first
    done;
    entries := Array.of_list !next
  in
  Base.Effect.on_change
    ~equal:(fun _ _ -> false)
    source
    (fun ~prev:_ ~next -> reconcile next);
  on_dispose (fun () -> Array.iter (fun e -> e.dispose ()) !entries)

let start ~adopt container f =
  let ctx =
    {
      doc = Web.owner_document container;
    }
  in
  let (), dispose =
    Base.mount (fun () ->
        let n = f () in
        if not adopt then Web.clear container "";
        let pos = { ctx; parent = container; cur = Web.first_child container; adopt; svg = false } in
        if Dev.on then begin
          mount_node pos (ref false) n;
          if adopt then walk_region pos (fun x -> Dev.mismatch container "nothing" (Some x))
        end
        else mount_node pos (ref false) n)
  in
  dispose

let render container f = start ~adopt:false container f
let hydrate container f = start ~adopt:true container f
let on_error : (string -> unit) ref = ref ignore

let cleanup_table : (unit -> unit) Web.table option ref = ref None

let cleanups () =
  match !cleanup_table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      cleanup_table := Some t;
      t

let set_cleanup id f = Web.table_set (cleanups ()) (string_of_int id) f
let drop_cleanup id = Web.table_delete (cleanups ()) (string_of_int id)
let live_islands : Web.node list ref = ref []
let next_cleanup = ref 0

let register cleanup =
  incr next_cleanup;
  set_cleanup !next_cleanup cleanup;
  !next_cleanup

let field name fields =
  List.find_map (fun (k, v) -> if String.equal k name then Some v else None) fields

let has_value value id = match value with Some v -> String.equal v id | None -> false

let transport name input =
  let result, resolve, fail = Async.make () in
  let id = register ignore in
  let finish () = drop_cleanup id in
  let abort =
    Web.fetch_post
    ("/_yuka/action/" ^ Web.encode_uri name)
    (Json.to_string input)
    (fun status body ->
      finish ();
      match Json.of_string body with
      | Ok (`Assoc fields) -> (
          match (field "ok" fields, field "error" fields) with
          | Some value, _ ->
              !Platform.acted ();
              resolve value
          | None, Some (`String message) -> fail message
          | None, _ ->
              fail
                ("action " ^ name ^ ": unexpected response (HTTP "
               ^ string_of_int status ^ ")"))
      | Ok _ | Error _ ->
          fail
            ("action " ^ name ^ ": response is not JSON (HTTP "
           ^ string_of_int status ^ ")"))
    (fun cancelled message ->
      finish ();
      if cancelled then fail "cancelled"
      else fail ("action " ^ name ^ ": network error: " ^ message))
  in
  if Web.table_has (cleanups ()) (string_of_int id) then begin
    set_cleanup id abort;
    match (match !acting with Some o -> Some o | None -> !Base.current_owner) with
    | Some owner ->
        let disposer = Base.add_disposer owner abort in
        Async.on_settled result (fun _ -> Base.remove_disposer owner disposer)
    | None -> ()
  end;
  result

let async_value id =
  let result, resolve, fail = Async.make () in
  let find () =
    let found =
      List.find_opt
        (fun s -> has_value (Web.get_attribute s "data-yuka-async") id)
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
            match (field "ok" fields, field "error" fields) with
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
            (fun s -> has_value (Web.get_attribute s "data-yuka-async") id)
            (Array.append own (Web.query_all n "script[data-yuka-async]")))
        nodes
    in
    let disconnect =
      Web.watch_added (fun nodes ->
          touches nodes
          && find ()
          && (drop_cleanup cleanup_id;
              true))
    in
    set_cleanup cleanup_id disconnect
  end;
  result

let started_key = "__yuka_started"
let is_true = function Some true -> true | Some false | None -> false

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
    Web.console_error ("yuka island " ^ id ^ " (" ^ name ^ "): " ^ reason);
    None
  in
  let entry = List.find_opt (fun e -> e.name = name) entries in
  match (entry, Web.table_get props id) with
  | None, _ -> fail "unknown island name"
  | _, None -> fail "props script not found"
  | Some entry, Some text -> (
      match Json.of_string text with
      | Error message -> fail ("bad props JSON: " ^ message)
      | Ok json -> (
          match entry.decode json with
          | Error message -> fail ("cannot decode props: " ^ message)
          | Ok build -> (
              let failed = ref false and dispose = ref ignore in
              let report e =
                let m = "yuka island " ^ id ^ " (" ^ name ^ "): " ^ Web.exn_to_string e in
                Web.console_error m;
                try !on_error m with _ -> ()
              in
              let stop d = try d () with e -> report e in
              let catch e =
                if not !failed then begin
                  failed := true;
                  let late = try !dispose (); None with d -> Some d in
                  report e;
                  Option.iter report late
                end
              in
              let o = Base.new_owner () in
              o.catch <- Some catch;
              match Base.with_owner o (fun () -> hydrate island build) with
              | d when !failed ->
                  stop d;
                  None
              | d ->
                  dispose := d;
                  Some d
              | exception e ->
                  catch e;
                  None)))

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
  let pending = Web.table_values (cleanups ()) in
  Web.table_clear (cleanups ());
  Array.iter (fun f -> f ()) pending;
  List.iter (fun island -> Web.set_bool island started_key false) !live_islands;
  live_islands := []

let cleanup_key = "__yuka_cleanup"

let stop_within el =
  let inside, outside = List.partition (fun island -> Web.contains el island) !live_islands in
  live_islands := outside;
  List.iter
    (fun island ->
      (match (Web.get_prop island cleanup_key : int option) with
      | Some id -> (
          let key = string_of_int id in
          match Web.table_get (cleanups ()) key with
          | Some f ->
              Web.table_delete (cleanups ()) key;
              f ()
          | None -> ())
      | None -> ());
      Web.set_bool island started_key false)
    inside

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
  Web.set_prop island cleanup_key id;
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
        set_cleanup id dispose;
        replay_events ()
    | None ->
        drop_cleanup id;
        drop_events ()
  in
  let run () =
    fired := true;
    match if known then None else load_lazy lazy_entries name with
    | None -> finish (boot entries props island)
    | Some (promise, forget) ->
        let cancelled = ref false in
        set_cleanup id (fun () ->
            cancelled := true;
            drop_events ());
        let report reason =
          finish None;
          Web.console_error
            ("yuka island "
            ^ Option.value (Web.get_attribute island "data-id") ~default:""
            ^ " (" ^ name ^ "): cannot load code: " ^ reason)
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
    set_cleanup id (fun () ->
        cancel ();
        drop_events ())

let script_props script =
  match Web.get_attribute script "data-yuka-props" with
  | Some id -> Some (id, Web.text_content script)
  | None -> None

let start ?(lazy_entries = []) entries =
  Action.transport := transport;
  Types.async_source := async_value;
  let props = Web.table () in
  let waiting = ref [] in
  let island_id island =
    Option.value (Web.get_attribute island "data-id") ~default:""
  in
  let start_waiting ~final =
    let ready, rest =
      List.partition (fun (id, _) -> final || Web.table_has props id) !waiting
    in
    waiting := rest;
    List.iter
      (fun (_, island) ->
        let started : bool option = Web.get_prop island started_key in
        if not (is_true started) then
          start_island entries lazy_entries props island)
      (List.rev ready)
  in
  let note_island island =
    let started : bool option = Web.get_prop island started_key in
    if not (is_true started) then begin
      let id = island_id island in
      waiting :=
        if List.exists (fun (i, _) -> String.equal i id) !waiting then
          List.map (fun (i, n) -> if i = id then (i, island) else (i, n)) !waiting
        else (id, island) :: !waiting
    end
  in
  let note_script ~final script =
    match script_props script with
    | Some (id, text) ->
        if final || Result.is_ok (Json.of_string text) then
          Web.table_set props id text
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
      drop_cleanup id
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
    set_cleanup id release
  end

type registry = { entries : Island.entry list; lazy_registry : lazy_entry list }

let registry ?(lazy_entries = []) entries = { entries; lazy_registry = lazy_entries }
