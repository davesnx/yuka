let fail = Cli.fail
let read path = In_channel.with_open_bin path In_channel.input_all
let extension = ".messages"

type part = Text of string | Arg of string
type message = { key : string; line : int; parts : part list }
type locale = { tag : string; file : string; messages : message list }

let reserved = [ "locales"; "base"; "tag"; "of_tag"; "locale_param"; "locale_codec"; "context"; "current" ]

let valid_tag tag =
  tag <> ""
  && (match tag.[0] with 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false)
  && String.for_all (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' -> true | _ -> false) tag

let constructor tag = String.capitalize_ascii (String.map (function '-' -> '_' | c -> c) tag)

let parts ~where text =
  let n = String.length text in
  let b = Buffer.create n in
  let flush acc = if Buffer.length b = 0 then acc else
      let s = Buffer.contents b in
      Buffer.clear b;
      Text s :: acc
  in
  let rec go i acc =
    if i >= n then List.rev (flush acc)
    else
      match text.[i] with
      | '{' when i + 1 < n && text.[i + 1] = '{' -> Buffer.add_char b '{'; go (i + 2) acc
      | '}' when i + 1 < n && text.[i + 1] = '}' -> Buffer.add_char b '}'; go (i + 2) acc
      | '}' -> fail "%s: a } with no {; write }} for the character" where
      | '{' -> (
          match String.index_from_opt text i '}' with
          | None -> fail "%s: a { with no }; write {{ for the character" where
          | Some e ->
              let name = String.sub text (i + 1) (e - i - 1) in
              if not (Yuka_routes.is_label name) then
                fail "%s: {%s} is not a valid argument name; use a lowercase OCaml name" where name;
              if name = "locale" then fail "%s: {locale} is the first argument of each message; choose another name" where;
              go (e + 1) (Arg name :: flush acc))
      | c -> Buffer.add_char b c; go (i + 1) acc
  in
  let parts = go 0 [] in
  List.iter
    (function
      | Text s when Source_text.find_from ~sub:"|js}" s 0 <> None -> fail "%s: the text cannot contain |js}" where
      | _ -> ())
    parts;
  parts

let trim_left s =
  let n = String.length s in
  let rec at i = if i < n && (s.[i] = ' ' || s.[i] = '\t') then at (i + 1) else i in
  let i = at 0 in
  String.sub s i (n - i)

let trim_right s =
  let rec at i = if i > 0 && (s.[i - 1] = ' ' || s.[i - 1] = '\t' || s.[i - 1] = '\r') then at (i - 1) else i in
  String.sub s 0 (at (String.length s))

let parse_file file =
  let lines = String.split_on_char '\n' (read file) in
  let messages =
    List.concat
      (List.mapi
         (fun i raw ->
           let line = i + 1 in
           let where = Printf.sprintf "%s:%d" file line in
           let s = trim_left (trim_right raw) in
           if s = "" || s.[0] = '#' then []
           else
             match String.index_opt s '=' with
             | None -> fail "%s: expected key = text" where
             | Some e ->
                 let key = trim_right (String.sub s 0 e) in
                 if not (Yuka_routes.is_label key) then
                   fail "%s: %S is not a valid key; use a lowercase OCaml name that is not a keyword" where key;
                 if List.mem key reserved then fail "%s: the key %s is a name of the generated module; choose another key" where key;
                 [ { key; line; parts = parts ~where (trim_left (String.sub s (e + 1) (String.length s - e - 1))) } ])
         lines)
  in
  let _ =
    List.fold_left
      (fun seen m ->
        (match List.assoc_opt m.key seen with
        | Some first -> fail "%s:%d: the key %s is already at line %d" file m.line m.key first
        | None -> ());
        (m.key, m.line) :: seen)
      [] messages
  in
  messages

let args m =
  List.fold_left (fun acc p -> match p with Arg a when not (List.mem a acc) -> acc @ [ a ] | _ -> acc) [] m.parts

let same_set a b = List.for_all (fun x -> List.mem x b) a && List.for_all (fun x -> List.mem x a) b

let check ~base locales =
  List.iter
    (fun l ->
      List.iter
        (fun m ->
          match List.find_opt (fun (b : message) -> b.key = m.key) base.messages with
          | None -> fail "%s:%d: the key %s is not in %s" l.file m.line m.key base.file
          | Some b ->
              if not (same_set (args m) (args b)) then
                fail "%s:%d: %s takes {%s}, but %s:%d takes {%s}" l.file m.line m.key
                  (String.concat "}, {" (args m))
                  base.file b.line
                  (String.concat "}, {" (args b)))
        l.messages;
      List.iter
        (fun (b : message) ->
          if not (List.exists (fun m -> m.key = b.key) l.messages) then
            fail "%s: no message %s (%s:%d)" l.file b.key base.file b.line)
        base.messages)
    locales

let expression parts =
  match parts with
  | [] -> "\"\""
  | _ -> String.concat " ^ " (List.map (function Text s -> "{js|" ^ s ^ "|js}" | Arg a -> a) parts)

let labels m = String.concat "" (List.map (fun a -> " ~" ^ a) (args m))

let print ~base locales =
  let p fmt = Printf.printf fmt in
  let ctor l = constructor l.tag in
  p "type locale = %s\n\n" (String.concat " | " (List.map ctor locales));
  p "let locales = [ %s ]\n" (String.concat "; " (List.map ctor locales));
  p "let base = %s\n" (ctor base);
  p "let tag = function %s\n"
    (String.concat " | " (List.map (fun l -> Printf.sprintf "%s -> %S" (ctor l) l.tag) locales));
  p "let of_tag = function %s | _ -> None\n"
    (String.concat " | " (List.map (fun l -> Printf.sprintf "%S -> Some %s" l.tag (ctor l)) locales));
  p "let locale_param = Yuka.Router.Param.make ~decode:of_tag ~encode:tag\n\n";
  p "let locale_codec =\n\
    \  Yuka.Codec.make\n\
    \    ~encode:(fun locale -> `String (tag locale))\n\
    \    ~decode:(function\n\
    \      | `String text -> ( match of_tag text with Some locale -> Ok locale | None -> Error (\"unknown locale \" ^ text))\n\
    \      | _ -> Error \"a locale is a string\")\n\n";
  p "let context : locale Yuka.Context.t = Yuka.Context.make ~name:\"yuka.locale\" ~codec:locale_codec ()\n";
  p "let current () = match Yuka.Context.get context with Some locale -> locale | None -> base\n";
  List.iter
    (fun l ->
      p "\nmodule %s = struct\n" (ctor l);
      List.iter (fun m -> p "  let %s%s = %s\n" m.key (labels m) (expression m.parts)) l.messages;
      p "end\n")
    locales;
  List.iter
    (fun (b : message) ->
      p "\nlet %s locale%s =\n  match locale with\n" b.key (labels b);
      List.iter
        (fun l ->
          let m = List.find (fun m -> m.key = b.key) l.messages in
          p "  | %s -> %s\n" (ctor l) (expression m.parts))
        locales)
    base.messages

let command =
  let dir = ref "" and base = ref "" in
  ( { Cli.name = "i18n";
      usage =
        "usage: yuka i18n --dir DIR --base LOCALE\n\
         Print the OCaml module of the messages in DIR/LOCALE.messages, one file per locale.";
      specs =
        [ ("--dir", Arg.Set_string dir, "DIR The directory of the .messages files");
          ("--base", Arg.Set_string base, "LOCALE The locale whose keys every other locale must have") ] },
    dir,
    base )

let main argv =
  let c, dir, base = command in
  Cli.parse c argv;
  if !dir = "" then Cli.usage_error c "give --dir";
  if !base = "" then Cli.usage_error c "give --base";
  Cli.run c (fun () ->
      let locales =
        Sys.readdir !dir |> Array.to_list |> List.sort compare
        |> List.filter (fun name -> Filename.check_suffix name extension)
        |> List.map (fun name ->
               let tag = Filename.chop_suffix name extension in
               let file = Filename.concat !dir name in
               if not (valid_tag tag) then
                 fail "%s: %S is not a locale name; use letters, digits and -, starting with a letter" file tag;
               { tag; file; messages = parse_file file })
      in
      List.iter
        (fun l ->
          match List.find_opt (fun o -> o != l && constructor o.tag = constructor l.tag) locales with
          | Some o -> fail "%s and %s give the same OCaml name %s" o.file l.file (constructor l.tag)
          | None -> ())
        locales;
      match List.find_opt (fun l -> l.tag = !base) locales with
      | None -> fail "%s: no file %s%s for the base locale" !dir !base extension
      | Some b ->
          check ~base:b locales;
          print ~base:b locales)
