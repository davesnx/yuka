(* Writes the native side of a yuka.web module from its .melange.ml: every external becomes a
   value of the same type, a function of all its arguments that raises "browser only", and Melange's Dom types become
   the abstract ones of Dom_native. So the native build has the same names, labels and types,
   and no member can drift from its binding. *)

open Ppxlib

let loc = Location.none

let rewrite =
  object
    inherit Ast_traverse.map as super

    method! attributes _ = []

    method! longident l =
      match l with Ldot (Lident "Dom", x) -> Ldot (Lident "Dom_native", x) | l -> super#longident l

    method! structure_item item =
      match item.pstr_desc with
      | Pstr_primitive { pval_name; pval_type; _ } ->
          let ty = super#core_type pval_type in
          let rec stub ty =
            match ty.ptyp_desc with
            | Ptyp_arrow (label, _, rest) ->
                Ast_builder.Default.pexp_fun ~loc label None (Ast_builder.Default.ppat_any ~loc) (stub rest)
            | _ -> [%expr browser_only ()]
          in
          let body = match ty.ptyp_desc with Ptyp_arrow _ -> stub ty | _ -> [%expr Obj.magic ()] in
          let pat = Ast_builder.Default.ppat_var ~loc pval_name in
          [%stri let [%p pat] : [%t ty] = [%e body]]
      | _ -> super#structure_item item
  end

let () =
  let file = Sys.argv.(1) in
  let source = In_channel.with_open_bin file In_channel.input_all in
  let lexbuf = Lexing.from_string source in
  Lexing.set_filename lexbuf file;
  let structure = rewrite#structure (Parse.implementation lexbuf) in
  print_string "(* Generated from ";
  print_string (Filename.basename file);
  print_string " by web/gen/native_side.ml: do not edit. *)\n\n";
  print_string "let browser_only () = invalid_arg \"yuka.web: browser only\"\n\n";
  Format.printf "%a@." Pprintast.structure structure
