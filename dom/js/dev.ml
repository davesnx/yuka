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
