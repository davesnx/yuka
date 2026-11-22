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

let names : (Obj.t -> string -> unit[@u]) * (Obj.t -> string option[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? (function () {
      var m = new WeakMap();
      return [function (o, s) { m.set(o, s) }, function (o) { return m.get(o) }];
    })() : 0|}]

let name o s = (fst names) (Obj.repr o) s [@u]
let name_of o = (snd names) (Obj.repr o) [@u]

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
