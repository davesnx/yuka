exception Fail of string

let fail fmt = Printf.ksprintf (fun s -> raise (Fail s)) fmt

type command = { name : string; usage : string; specs : (Arg.key * Arg.spec * Arg.doc) list }

let usage_error c fmt =
  Printf.ksprintf
    (fun m ->
      prerr_string ("yuka " ^ c.name ^ ": " ^ m ^ ".\n" ^ Arg.usage_string (Arg.align c.specs) c.usage);
      exit 2)
    fmt

let parse c argv =
  let anon a = raise (Arg.Bad ("unexpected argument " ^ a)) in
  match Arg.parse_argv ~current:(ref 0) argv (Arg.align c.specs) anon c.usage with
  | () -> ()
  | exception Arg.Help text ->
      print_string text;
      exit 0
  | exception Arg.Bad text ->
      prerr_string text;
      exit 2

let run c f =
  match f () with
  | () -> ()
  | exception Fail m ->
      prerr_endline ("yuka " ^ c.name ^ ": " ^ m);
      exit 1
  | exception Sys_error m ->
      prerr_endline ("yuka " ^ c.name ^ ": " ^ m);
      exit 1
