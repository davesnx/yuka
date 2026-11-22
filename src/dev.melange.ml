let on : bool = [%mel.raw {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__|}]

let report : (Web.node -> string -> Web.node option -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function report(parent, expected, found) {
      if (report.quiet) return;
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

external set_quiet : (Web.node -> string -> Web.node option -> unit[@u]) -> bool -> unit = "quiet" [@@mel.set]

let quiet b = set_quiet report b

let untracked : (unit -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? function () {
      console.error("[yuka] State.get with nothing tracking it, during the render of a component.\n  It reads one time and never updates. Read it in markup, a memo or an effect,\n  or use State.peek for one read.", new Error("State.get"));
    } : 0|}]

let untracked_get () = untracked () [@u]

let hot_parts : (Obj.t -> Web.node -> unit[@u]) * (Obj.t -> Obj.t -> Obj.t -> unit[@u]) * (Obj.t -> unit[@u]) =
  [%mel.raw
    {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__ ? (function () {
      var roots = new WeakMap();
      var root = function (owner, el) { roots.set(owner, el); el.__yuka_kept = []; };
      var keep = function (owner, encode, restore) {
        for (var o = owner; o; o = o.parent) {
          var el = roots.get(o);
          if (el) {
            var i = el.__yuka_kept.length, saved = el.__yuka_saved;
            el.__yuka_kept.push(encode);
            if (saved && i < saved.length && saved[i] !== undefined) {
              var m = restore(saved[i]);
              if (m !== undefined) console.warn("yuka dev: island " + el.getAttribute("data-name") + ": kept State " + (i + 1) + " starts again: " + m);
            }
            return;
          }
        }
      };
      var hot = function (swap) {
        window.__yuka_hot = function (urls) {
          return Promise.all(urls.map(function (u) { return import(u); })).then(function (ms) {
            var es = ms.map(function (m) {
              var e = m && m.register;
              return e && typeof e.name === "string" && typeof e.decode === "function" ? e : null;
            });
            if (es.indexOf(null) >= 0) return false;
            es.forEach(function (e) {
              var els = Array.prototype.filter.call(document.querySelectorAll("yuka-island"), function (el) {
                return el.getAttribute("data-name") === e.name;
              });
              els.forEach(function (el) {
                el.__yuka_saved = (el.__yuka_kept || []).map(function (f) { try { return f(); } catch (x) { return undefined; } });
              });
              try { swap(e, Promise.resolve(e)); }
              finally { els.forEach(function (el) { delete el.__yuka_saved; }); }
            });
            return true;
          });
        };
      };
      return [root, keep, hot];
    })() : 0|}]

let root owner el = (let f, _, _ = hot_parts in f) (Obj.repr owner) el [@u]
let keep owner encode restore = (let _, f, _ = hot_parts in f) (Obj.repr owner) (Obj.repr encode) (Obj.repr restore) [@u]
let hot swap = (let _, _, f = hot_parts in f) (Obj.repr swap) [@u]
