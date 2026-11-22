open Types

type cur = Web.node Js.null
type pos = { doc : Web.node; parent : Web.node; cur : cur; adopt : bool }

external next_sibling : Web.node -> cur = "nextSibling" [@@mel.get]
external first_child : Web.node -> cur = "firstChild" [@@mel.get]
external parent : Web.node -> cur = "parentNode" [@@mel.get]
external insert : Web.node -> Web.node -> cur -> unit = "insertBefore" [@@mel.send]
external node_of : cur -> Web.node = "%identity"
external create_fragment : Web.node -> Web.node = "createDocumentFragment" [@@mel.send]

let some n : cur = Js.Null.return n
let repr (pos : pos) = Obj.repr pos
let mount_node pos n = Client.mount_at (repr pos) (ref false) n

let rec remove_between start stop =
  let n = next_sibling start in
  if n != Js.null && node_of n != stop then begin
    Web.remove (node_of n);
    remove_between start stop
  end

let off_page : Web.node -> Web.node =
  [%mel.raw
    {|function (frag) {
  return {
    insertBefore: function (n, c) { (c ? c.parentNode : frag).insertBefore(n, c); },
    get lastChild() { return frag.lastChild; },
    ownerDocument: frag.ownerDocument,
    localName: ""
  };
}|}]

let nodes_from : cur -> cur -> Web.node array =
  [%mel.raw {|function (n, stop) { var out = []; for (; n && n !== stop; n = n.nextSibling) out.push(n); return out; }|}]

let off_page_mount pos n =
  let frag = create_fragment pos.doc in
  Client.mount_at (Client.off_page_at (repr pos) (off_page frag)) (ref false) n;
  (frag, nodes_from (first_child frag) Js.null)

let rec hold (p : boundary) n =
  match n with
  | Hole f -> Hole (held p f)
  | Fragment l -> Fragment (List.map (hold p) l)
  | Element { tag; attrs; children } -> Element { tag; attrs; children = List.map (hold p) children }
  | Template { template; parts } ->
      Template { template; parts = Array.map (function Child n -> Child (hold p n) | part -> part) parts }
  | Each { items; key; equal; render } -> Each { items; key; equal; render = (fun x -> hold p (render x)) }
  | Await { async; loading; failed; render } ->
      Await { async; loading = hold p loading; failed = (fun m -> hold p (failed m)); render = (fun v -> hold p (render v)) }
  | Catch { children; fallback; client } -> Catch { children; fallback; client = (fun pos -> hold p (client pos)) }
  | Provide { add; children; client; pending = None } ->
      Provide { add; children; pending = None; client = (fun pos -> hold p (client pos)) }
  | Provide { pending = Some _; _ } | Text _ | Island _ | Slot _ -> n

and held p f =
  let shown = ref [||] and mounted = ref false in
  fun () ->
    let changed = p.mark () in
    let n = hold p (f ()) in
    let client pos =
      let pos : pos = Obj.obj pos in
      (if not !mounted then begin
         mounted := true;
         if pos.adopt then begin
           let first = pos.cur in
           mount_node pos n;
           shown := nodes_from first pos.cur
         end
         else begin
           let frag, next = off_page_mount pos n in
           shown := next;
           insert pos.parent frag pos.cur
         end
       end
       else
         let frag, next = off_page_mount pos n in
         if changed () then begin
           let stop = pos.cur and old = !shown and live = ref true in
           Base.own (fun () -> live := false);
           Array.iter (fun x -> insert pos.parent x stop) old;
           p.on_switch (fun () ->
               if !live then begin
                 Array.iter Web.remove old;
                 insert pos.parent frag stop;
                 shown := next
               end)
         end
         else begin
           insert pos.parent frag pos.cur;
           shown := next
         end);
      Fragment []
    in
    Provide { add = (fun e -> e); children = (fun () -> n); client; pending = None }

let mount pos fallback children (boundary : unit -> boundary) =
  let pos : pos = Obj.obj pos in
  let o = Base.new_owner () in
  Base.own (fun () -> Base.dispose_owner o);
  let p = boundary () in
  o.env <- p.bind o.env;
  let ids = Types.next_id () ^ "-" in
  let inside f = Base.with_owner o (fun () -> Types.with_browser_ids ids f) in
  let tree = hold p (Base.with_owner o (fun () -> Scheduler.untrack children)) in
  p.built ();
  let start = Client.hole_start_at (repr pos) in
  let filling =
    pos.adopt && String.length (Web.data start) > 2 && (Web.data start).[1] = 's' && Web.ready_state () = "loading"
  in
  if filling then Web.set_data start "[";
  let marked =
    pos.adopt && pos.cur != Js.null && Web.node_type (node_of pos.cur) = 8 && Web.data (node_of pos.cur) = "[?"
  in
  let shown = filling || marked in
  if pos.adopt && (not shown) && p.idle () then begin
    inside (fun () -> mount_node pos tree);
    p.reveal ();
    Client.drop_rest_at (repr pos);
    ignore (Client.comment_at (repr pos) "]")
  end
  else begin
    let frag, _ = inside (fun () -> off_page_mount pos tree) in
    let dispose = ref ignore in
    if pos.adopt && not shown then Client.skip_region (repr pos)
    else if shown || not (p.idle ()) then begin
      let (), d =
        Base.mount (fun () ->
            Types.with_browser_ids ids (fun () ->
                if marked then begin
                  ignore (Client.hole_start_at (repr pos));
                  mount_node pos fallback;
                  Client.drop_rest_at (repr pos);
                  ignore (Client.comment_at (repr pos) "]")
                end
                else mount_node pos fallback))
      in
      Base.own d;
      dispose := d
    end;
    let stop = Client.comment_at (repr pos) "]" in
    p.on_idle (fun () ->
        !dispose ();
        remove_between start stop;
        insert (node_of (parent stop)) frag (some stop);
        p.reveal ())
  end
