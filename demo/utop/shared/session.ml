(* Fake utop sessions: what a user typed and what utop answered. Nothing here runs
   OCaml; the answers are written by hand, in the words of OCaml 5.3. *)

type entry = { input : string; output : string } [@@deriving codec]

type t = {
  file : string;  (** The name in the project panel, as [lists.ml]. *)
  started : int;  (** The clock of the first prompt, in seconds after midnight. *)
  entries : entry list;
}
[@@deriving codec]

let entry input output = { input; output }

let lists =
  {
    file = "lists.ml";
    started = (18 * 3600) + (6 * 60) + 39;
    entries =
      [
        entry "let xs = [1; 2; 3; 4; 5];;" "val xs : int list = [1; 2; 3; 4; 5]";
        entry "List.map (fun x -> x * x) xs;;" "- : int list = [1; 4; 9; 16; 25]";
        entry "List.fold_left ( + ) 0 xs;;" "- : int = 15";
        entry "List.filter (fun x -> x mod 2 = 0) xs;;" "- : int list = [2; 4]";
        entry "List.nth xs 10;;" "Exception: Failure \"nth\".";
      ];
  }

let records =
  {
    file = "records.ml";
    started = (9 * 3600) + (41 * 60) + 2;
    entries =
      [
        entry "type point = { x : float; y : float };;" "type point = { x : float; y : float; }";
        entry "let origin = { x = 0.; y = 0. };;" "val origin : point = {x = 0.; y = 0.}";
        entry "let dist a b = Float.hypot (a.x -. b.x) (a.y -. b.y);;" "val dist : point -> point -> float = <fun>";
        entry "dist origin { x = 3.; y = 4. };;" "- : float = 5.";
        entry "{ origin with y = 2. };;" "- : point = {x = 0.; y = 2.}";
      ];
  }

let variants =
  {
    file = "variants.ml";
    started = (14 * 3600) + (17 * 60) + 55;
    entries =
      [
        entry "type shape = Circle of float | Rect of float * float;;"
          "type shape = Circle of float | Rect of float * float";
        entry "let area = function Circle r -> Float.pi *. r *. r | Rect (w, h) -> w *. h;;"
          "val area : shape -> float = <fun>";
        entry "List.map area [Circle 1.; Rect (2., 3.)];;" "- : float list = [3.14159265358979312; 6.]";
        entry "let name = function Circle _ -> \"circle\";;"
          "Line 1, characters 11-40:\n\
           Warning 8 [partial-match]: this pattern-matching is not exhaustive.\n\
           Here is an example of a case that is not matched:\n\
           Rect (_, _)\n\
           val name : shape -> string = <fun>";
      ];
  }

let modules =
  {
    file = "modules.ml";
    started = (22 * 3600) + (3 * 60) + 12;
    entries =
      [
        entry "module Counter = struct let count = ref 0 let next () = incr count; !count end;;"
          "module Counter : sig val count : int ref val next : unit -> int end";
        entry "Counter.next (); Counter.next ();;" "- : int = 2";
        entry "#show_type option;;" "type 'a option = None | Some of 'a";
        entry "\"hello\" ^ 42;;"
          "Line 1, characters 10-12:\n\
           Error: The constant 42 has type int but an expression was expected of type\n\
          \         string";
        entry "String.concat \", \" [\"utop\"; \"in\"; \"Zed\"];;" "- : string = \"utop, in, Zed\"";
      ];
  }

let all = [ lists; records; variants; modules ]
let find file = List.find_opt (fun session -> session.file = file) all

(* Phrases that every session answers, so the prompt shows more than the history. *)
let extra =
  [
    entry "#utop_help;;"
      "If colors look too bright, try: UTop.set_profile UTop.Light\n\n\
       Utop does not run here: this is a demo of Yuka, with answers written in advance.\n\
       Try integer arithmetic (1 + 2 * 3;;), let x = 6 * 7;; or a phrase of the history.";
    entry "#help;;" "Use #utop_help;; for the commands of this fake utop.";
    entry "\"hello\" ^ \" world\";;" "- : string = \"hello world\"";
    entry "#quit;;" "";
    entry "Sys.ocaml_version;;" "- : string = \"5.3.0\"";
    entry "print_endline \"Hello, Zed!\";;" "Hello, Zed!\n- : unit = ()";
  ]

let ocaml_version = "5.3.0"
let utop_version = "2.15.0"
