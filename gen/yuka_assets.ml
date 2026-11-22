let fail = Cli.fail
let read path = In_channel.with_open_bin path In_channel.input_all
let byte s i = Char.code s.[i]
let be16 s i = (byte s i lsl 8) lor byte s (i + 1)
let be32 s i = (be16 s i lsl 16) lor be16 s (i + 2)
let le16 s i = byte s i lor (byte s (i + 1) lsl 8)
let le24 s i = le16 s i lor (byte s (i + 2) lsl 16)
let le32 s i = le24 s i lor (byte s (i + 3) lsl 24)

let has s at sub =
  String.length s >= at + String.length sub && String.equal (String.sub s at (String.length sub)) sub

let rec jpeg s i =
  let n = String.length s in
  if i + 1 >= n || byte s i <> 0xff then None
  else
    let m = byte s (i + 1) in
    if m = 0xff then jpeg s (i + 1)
    else if m = 0x01 || (m >= 0xd0 && m <= 0xd8) then jpeg s (i + 2)
    else if i + 3 >= n then None
    else if m >= 0xc0 && m <= 0xcf && m <> 0xc4 && m <> 0xc8 && m <> 0xcc then
      if i + 8 < n then Some (be16 s (i + 7), be16 s (i + 5)) else None
    else jpeg s (i + 2 + be16 s (i + 2))

let size s =
  let n = String.length s in
  if has s 0 "\x89PNG\r\n\x1a\n" && has s 12 "IHDR" && n >= 24 then Some (be32 s 16, be32 s 20)
  else if (has s 0 "GIF87a" || has s 0 "GIF89a") && n >= 10 then Some (le16 s 6, le16 s 8)
  else if has s 0 "RIFF" && has s 8 "WEBP" then
    if has s 12 "VP8 " && n >= 30 then Some (le16 s 26 land 0x3fff, le16 s 28 land 0x3fff)
    else if has s 12 "VP8L" && n >= 25 then
      let v = le32 s 21 in
      Some ((v land 0x3fff) + 1, ((v lsr 14) land 0x3fff) + 1)
    else if has s 12 "VP8X" && n >= 30 then Some (le24 s 24 + 1, le24 s 27 + 1)
    else None
  else if has s 0 "\xff\xd8" then jpeg s 2
  else None

let extensions = [ ".png"; ".jpg"; ".jpeg"; ".gif"; ".webp" ]

let ident stem =
  let s = String.map (fun c -> match c with 'a' .. 'z' | '0' .. '9' | '_' -> c | 'A' .. 'Z' -> Char.lowercase_ascii c | _ -> '_') stem in
  match s.[0] with 'a' .. 'z' | '_' -> s | _ -> "image_" ^ s

let on_path name =
  match Sys.getenv_opt "PATH" with
  | None -> false
  | Some path ->
      List.exists
        (fun dir -> dir <> "" && Sys.file_exists (Filename.concat dir name))
        (String.split_on_char ':' path)

let write out name ext data =
  let file = Printf.sprintf "%s-%s%s" name (String.sub (Digest.to_hex (Digest.string data)) 0 8) ext in
  Out_channel.with_open_bin (Filename.concat out file) (fun oc -> Out_channel.output_string oc data);
  "/_yuka/img/" ^ file

let resized ~out ~src ~name ~ext width =
  let tmp = Filename.concat out (Printf.sprintf ".%s-%d%s" name width ext) in
  let command = Printf.sprintf "vips thumbnail %s %s %d" (Filename.quote src) (Filename.quote tmp) width in
  if Sys.command command <> 0 then fail "%s: %s failed" src command;
  let data = read tmp in
  Sys.remove tmp;
  match size data with
  | Some (w, _) -> (write out (Printf.sprintf "%s-%dw" name w) ext data, w)
  | None -> fail "%s: vips wrote a file with no size" src

let image ~out ~widths path =
  let base = Filename.basename path in
  let ext = String.lowercase_ascii (Filename.extension base) in
  let name = ident (Filename.remove_extension base) in
  let data = read path in
  match size data with
  | None -> fail "%s: not a PNG, JPEG, GIF or WebP file" path
  | Some (width, height) ->
      let src = write out name ext data in
      let copies = List.map (resized ~out ~src:path ~name ~ext) (List.filter (fun w -> w < width) widths) in
      (name, src, width, height, List.sort (fun (_, a) (_, b) -> Int.compare a b) ((src, width) :: copies))

let parse_widths text =
  List.map
    (fun w -> match int_of_string_opt (String.trim w) with Some n when n > 0 -> n | _ -> fail "--widths: %S is not a width in pixels" w)
    (String.split_on_char ',' text)

let command =
  let dir = ref "" and out = ref "" and widths = ref "" in
  ( { Cli.name = "assets";
      usage =
        "usage: yuka assets --dir DIR --out DIR [--widths W,W...]\n\
         Copy each PNG, JPEG, GIF and WebP file of the images directory to the output directory with a hash in its name, and print the OCaml module with one Yuka.Image.t per file.\n\
         With --widths and the vips command on PATH, also write a smaller copy for each width under the width of the file.";
      specs =
        [
          ("--dir", Arg.Set_string dir, "DIR The directory of the images");
          ("--out", Arg.Set_string out, "DIR The directory to write the files to, served at /_yuka/img/");
          ("--widths", Arg.Set_string widths, "W,W... Widths in pixels of the smaller copies (needs vips)");
        ] },
    dir, out, widths )

let main argv =
  let c, dir, out, widths = command in
  Cli.parse c argv;
  if !dir = "" then Cli.usage_error c "give --dir";
  if !out = "" then Cli.usage_error c "give --out";
  Cli.run c (fun () ->
      let widths = if !widths = "" then [] else parse_widths !widths in
      let widths =
        if widths <> [] && not (on_path "vips") then begin
          prerr_endline "yuka assets: vips is not on PATH: no smaller copies";
          []
        end
        else widths
      in
      if not (Sys.file_exists !out) then Sys.mkdir !out 0o755;
      let files =
        Sys.readdir !dir |> Array.to_list |> List.sort String.compare
        |> List.filter (fun f -> f.[0] <> '.' && List.mem (String.lowercase_ascii (Filename.extension f)) extensions)
      in
      let names = List.map (fun f -> ident (Filename.remove_extension f)) files in
      List.iteri
        (fun i name ->
          if List.exists (String.equal name) (List.filteri (fun j _ -> j < i) names) then
            fail "two files of %s give the name %s" !dir name)
        names;
      let images = List.map (fun f -> image ~out:!out ~widths (Filename.concat !dir f)) files in
      List.iter
        (fun (name, src, width, height, srcset) ->
          Printf.printf "let %s : Yuka.Image.t =\n  { Yuka.Image.src = %S; width = %d; height = %d;\n    srcset = [ %s ] }\n" name src
            width height
            (String.concat "; " (List.map (fun (u, w) -> Printf.sprintf "(%S, %d)" u w) srcset)))
        images)
