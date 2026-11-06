open Ppxlib
open Ast_builder.Default

let snake name =
  let b = Buffer.create 16 in
  String.iteri
    (fun i c ->
      if c >= 'A' && c <= 'Z' then (
        if i > 0 && name.[i - 1] <> '_' then Buffer.add_char b '_';
        Buffer.add_char b (Char.lowercase_ascii c))
      else Buffer.add_char b c)
    name;
  Buffer.contents b

let expand ~ctxt (lid : Longident.t) path =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in
  let parts = Longident.flatten_exn lid in
  let name = String.concat "." parts in
  let last = List.nth parts (List.length parts - 1) in
  let file = Filename.basename path in
  let expected = snake last ^ ".js" in
  if file <> expected then
    Location.raise_errorf ~loc
      "[yuka] [%%yuka.lazy]: the file '%s' does not match the module '%s' (expected '%s')"
      file name expected;
  let js =
    Printf.sprintf
      "function(){ return import(%S).then(function(m){ return m.register; }) }" path
  in
  [%expr
    Yuka.Client.lazy_entry ~name:[%e estring ~loc name]
      ([%mel.raw [%e pexp_constant ~loc (Pconst_string (js, loc, Some ""))]]
        : unit -> Yuka.Client.entry Yuka.Client.promise)]

let extension =
  Extension.V3.declare "yuka.lazy" Extension.Context.expression
    Ast_pattern.(
      single_expr_payload
        (pexp_construct __ (some (estring __))))
    expand
