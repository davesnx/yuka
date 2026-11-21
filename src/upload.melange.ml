let form_files : Web.event -> (string * string * string * int) array =
  [%mel.raw
    {|function (ev) {
  const t = ev.target, el = t.localName === "form" ? t : t.form || t.closest("form"), out = [];
  new el.ownerDocument.defaultView.FormData(el).forEach(function (v, k) { if (typeof v !== "string" && (v.name || v.size)) out.push([k, v.name, v.type, v.size]); });
  return out;
}|}]

let upload_form :
    string -> Web.event -> (float -> unit) -> (int -> string -> unit) -> (bool -> string -> unit) -> unit -> unit =
  [%mel.raw
    {|function (url, ev, progress, ok, fail) {
  const t = ev.target, el = t.localName === "form" ? t : t.form || t.closest("form"), w = el.ownerDocument.defaultView;
  const data = new w.FormData(el), s = ev.submitter, x = new w.XMLHttpRequest();
  if (s && s.name) data.append(s.name, s.value);
  x.open("POST", url);
  x.upload.onprogress = function (e) { if (e.lengthComputable) progress(e.loaded / e.total); };
  x.onload = function () { ok(x.status, x.responseText); };
  x.onerror = function () { fail(false, "network error"); };
  x.onabort = function () { fail(true, "cancelled"); };
  x.send(data);
  return function () { x.abort(); };
}|}]

type t = Form_core.upload

let make limits : t =
  {
    limits;
    files =
      (fun ev ->
        List.map
          (fun (k, filename, content_type, size) ->
            ( k,
              Form_core.File
                {
                  filename;
                  content_type = (if content_type = "" then "application/octet-stream" else content_type);
                  size;
                  content = "";
                } ))
          (Array.to_list (form_files ev)));
    send = upload_form;
  }
