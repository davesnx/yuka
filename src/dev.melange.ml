let on : bool = [%mel.raw {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__|}]

let report : (Web.node -> string -> Web.node option -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function (parent, expected, found) {
      if (found != null) {
        if (found.__yuka_mismatch && expected === "nothing") return;
        found.__yuka_mismatch = true;
      }
      var describe = function (n) {
        if (n == null) return "nothing";
        if (n.nodeType === 1) return "<" + n.localName + ">";
        if (n.nodeType === 3) return JSON.stringify(n.data.length > 30 ? n.data.slice(0, 30) + "..." : n.data);
        if (n.nodeType === 8) return "<!--" + n.data + "-->";
        return n.nodeName;
      };
      var path = [], island = "", n = parent;
      while (n && n.nodeType === 1 && n.localName !== "body") {
        if (n.localName === "yuka-island") { island = n.getAttribute("data-name") || ""; break; }
        var i = 1, s = n;
        while ((s = s.previousElementSibling)) if (s.localName === n.localName) i++;
        path.unshift(i > 1 ? n.localName + ":" + i : n.localName);
        n = n.parentNode;
      }
      console.warn("yuka: hydration mismatch in island " + (island || "?") + " at " + (path.join(" > ") || "root") + ": expected " + expected + ", found " + describe(found));
    } : 0|}]

let mismatch parent expected found = report parent expected found [@u]

let untracked : (string option -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function (name) {
      console.error("[yuka] " + (name === undefined ? "" : name + ": ") + "State.get with nothing tracking it, during the render of a component.\n  It reads one time and never updates. Read it in markup, a memo or an effect,\n  or use State.peek for one read.", new Error("State.get"));
    } : 0|}]

let untracked_get name = untracked name [@u]

let registry :
    (Obj.t -> string -> unit[@u])
    * (Obj.t -> string option[@u])
    * (string -> string -> Obj.t -> unit[@u])
    * (Obj.t -> Obj.t -> unit[@u])
    * (Obj.t -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? (function () {
      var m = new WeakMap(), roots = new WeakMap(), islands = [], current = null;
      var live = function (x) { return x.owner.gen === x.gen };
      var shown = function (v, d) {
        if (v === undefined) return "None";
        if (v === null) return "null";
        var t = typeof v;
        if (t === "string") return JSON.stringify(v);
        if (t !== "object") return t === "function" ? "<fun>" : String(v);
        if (d > 3) return "...";
        var a = Array.isArray(v), l = [];
        if (!a && "hd" in v && "tl" in v) { a = true; for (var c = v; c && "hd" in c; c = c.tl) l.push(c.hd) }
        else if (a) l = v;
        var parts = a ? l.slice(0, 20).map(function (x) { return shown(x, d + 1) })
          : Object.keys(v).slice(0, 20).map(function (k) { return k + ": " + shown(v[k], d + 1) });
        if ((a ? l : Object.keys(v)).length > 20) parts.push("...");
        return a ? "[" + parts.join(", ") + "]" : "{" + parts.join(", ") + "}";
      };
      var value = function (v) { var s = shown(v, 0); return s.length > 200 ? s.slice(0, 200) + "..." : s };
      var path = function (o) {
        var p = [];
        for (; o; o = o.parent) { var s = m.get(o); if (s !== undefined) p.unshift(s) }
        return p.join(" > ");
      };
      globalThis.__yuka_dev = {
        islands: function () {
          islands = islands.filter(live);
          return islands.map(function (i) {
            i.states = i.states.filter(function (x) { return live(x) && x.node.state !== 3 });
            return {
              name: i.name,
              id: i.id,
              states: i.states.map(function (x) {
                var n = m.get(x.node), v;
                try { v = value(x.get()) } catch (e) { v = "raised an exception" }
                return { name: n === undefined ? "State #" + x.node.id : n, owner: path(x.owner), value: v };
              })
            };
          });
        }
      };
      return [
        function (o, s) { m.set(o, s) },
        function (o) { return m.get(o) },
        function (name, id, o) {
          islands = islands.filter(live);
          var i = { name: name, id: id, owner: o, gen: o.gen, states: [], max: 64 };
          islands.push(i);
          roots.set(o, i);
        },
        function (node, get) {
          if (current === null || islands.length === 0) return;
          var o = current();
          for (var p = o; p; p = p.parent) {
            var i = roots.get(p);
            if (i !== undefined) {
              if (!live(i)) return;
              i.states.push({ node: node, get: get, owner: o, gen: o.gen });
              if (i.states.length > i.max) {
                i.states = i.states.filter(function (x) { return live(x) && x.node.state !== 3 });
                i.max = 2 * i.states.length + 64;
              }
              return;
            }
          }
        },
        function (f) { current = f }
      ];
    })() : 0|}]

let name o s = (let f, _, _, _, _ = registry in f) (Obj.repr o) s [@u]
let name_of o = (let _, f, _, _, _ = registry in f) (Obj.repr o) [@u]
let island name id o = (let _, _, f, _, _ = registry in f) name id (Obj.repr o) [@u]
let state node get = (let _, _, _, f, _ = registry in f) (Obj.repr node) (Obj.repr get) [@u]
let owners current = (let _, _, _, _, f = registry in f) (Obj.repr current) [@u]

let report : (string -> Obj.t -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function (message, e) {
      console.error("[yuka] " + message, e);
    } : 0|}]

let error message e = report message e [@u]

let protect : ((unit -> Obj.t[@u]) -> (Obj.t -> unit[@u]) -> Obj.t[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function (f, failed) {
      try { return f() } catch (e) { failed(e); throw e }
    } : 0|}]

let guard f failed = protect f failed [@u]

let tracer :
    (bool -> unit[@u]) * (unit -> bool[@u]) * (Obj.t -> string -> unit[@u]) * (Obj.t -> string option[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? (function () {
      var on = false, m = new WeakMap();
      return [
        function (b) { on = b },
        function () { return on },
        function (o, s) { m.set(o, s) },
        function (o) { var s = m.get(o); m.delete(o); return s }
      ];
    })() : 0|}]

let set_trace b = (let f, _, _, _ = tracer in f) b [@u]
let tracing () = (let _, f, _, _ = tracer in f) () [@u]
let cause o s = (let _, _, f, _ = tracer in f) (Obj.repr o) s [@u]
let take_cause o = (let _, _, _, f = tracer in f) (Obj.repr o) [@u]

let print : (string -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function (message) {
      console.log("[yuka] " + message);
    } : 0|}]

let trace message = print message [@u]
