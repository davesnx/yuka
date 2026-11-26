let ( let* ) = Lwt.bind

type t = { fd : Lwt_unix.file_descr; mutable input : string }
type frame = Text of string | Close of int | Ping of string | Pong of string | Other of int

let fill t =
  let chunk = Bytes.create 65536 in
  let* n = Lwt_unix.read t.fd chunk 0 (Bytes.length chunk) in
  if n = 0 then Lwt.fail End_of_file
  else begin
    t.input <- t.input ^ Bytes.sub_string chunk 0 n;
    Lwt.return_unit
  end

let rec take t n =
  if String.length t.input >= n then begin
    let s = String.sub t.input 0 n in
    t.input <- String.sub t.input n (String.length t.input - n);
    Lwt.return s
  end
  else Lwt.bind (fill t) (fun () -> take t n)

let rec head t =
  let rec at i = if i + 4 > String.length t.input then None else if String.sub t.input i 4 = "\r\n\r\n" then Some i else at (i + 1) in
  match at 0 with
  | Some stop ->
      let text = String.sub t.input 0 stop in
      t.input <- String.sub t.input (stop + 4) (String.length t.input - stop - 4);
      Lwt.return text
  | None -> Lwt.bind (fill t) (fun () -> head t)

let write fd text =
  let rec from off =
    if off = String.length text then Lwt.return_unit
    else Lwt.bind (Lwt_unix.write_string fd text off (String.length text - off)) (fun n -> from (off + n))
  in
  from 0

(* The accept value of RFC 6455 for the key below. *)
let accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

let connect fd ~host ~cookie =
  let t = { fd; input = "" } in
  let request =
    String.concat "\r\n"
      ([
         "GET /_yuka/live HTTP/1.1";
         "Host: " ^ host;
         "Origin: http://" ^ host;
         "Upgrade: websocket";
         "Connection: Upgrade";
         "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==";
         "Sec-WebSocket-Version: 13";
       ]
      @ (match cookie with Some c -> [ "Cookie: " ^ c ] | None -> [])
      @ [ ""; "" ])
  in
  let* () = write fd request in
  let* text = head t in
  let lines = List.map String.trim (String.split_on_char '\n' text) in
  let status = List.hd lines in
  (if String.starts_with ~prefix:"HTTP/1.1 101 " status then
     let field name =
       List.find_map
         (fun line ->
           match String.index_opt line ':' with
           | Some i when String.lowercase_ascii (String.sub line 0 i) = name ->
               Some (String.trim (String.sub line (i + 1) (String.length line - i - 1)))
           | _ -> None)
         (List.tl lines)
     in
     let has_token name token =
       match field name with
       | Some v -> List.exists (fun t -> String.lowercase_ascii (String.trim t) = token) (String.split_on_char ',' v)
       | None -> false
     in
     if field "sec-websocket-accept" <> Some accept then
       failwith ("Ws.connect: a 101 without the right Sec-WebSocket-Accept: " ^ text);
     if not (has_token "upgrade" "websocket") then failwith ("Ws.connect: a 101 without Upgrade: websocket: " ^ text);
     if not (has_token "connection" "upgrade") then failwith ("Ws.connect: a 101 without Connection: Upgrade: " ^ text));
  Lwt.return (t, status)

let frame ~opcode payload =
  let n = String.length payload in
  let length =
    if n < 126 then String.make 1 (Char.chr (0x80 lor n))
    else if n < 65536 then Printf.sprintf "%c%c%c" (Char.chr (0x80 lor 126)) (Char.chr (n lsr 8)) (Char.chr (n land 255))
    else String.make 1 (Char.chr (0x80 lor 127)) ^ String.init 8 (fun i -> Char.chr ((n lsr (8 * (7 - i))) land 255))
  in
  let mask = "\x12\x34\x56\x78" in
  String.make 1 (Char.chr (0x80 lor opcode))
  ^ length ^ mask
  ^ String.mapi (fun i c -> Char.chr (Char.code c lxor Char.code mask.[i land 3])) payload

let send t text = write t.fd (frame ~opcode:1 text)
let ping t payload = write t.fd (frame ~opcode:9 payload)
let close t code = write t.fd (frame ~opcode:8 (Printf.sprintf "%c%c" (Char.chr (code lsr 8)) (Char.chr (code land 255))))

let receive t =
  let* h = take t 2 in
  let opcode = Char.code h.[0] land 15 and short = Char.code h.[1] land 127 in
  let* n =
    if short = 126 then Lwt.map (fun s -> (Char.code s.[0] lsl 8) lor Char.code s.[1]) (take t 2)
    else if short = 127 then Lwt.map (fun s -> String.fold_left (fun acc c -> (acc lsl 8) lor Char.code c) 0 s) (take t 8)
    else Lwt.return short
  in
  let* payload = take t n in
  Lwt.return
    (match opcode with
    | 1 -> Text payload
    | 8 -> Close (if n >= 2 then (Char.code payload.[0] lsl 8) lor Char.code payload.[1] else 1005)
    | 9 -> Ping payload
    | 10 -> Pong payload
    | o -> Other o)

let show = function
  | Text s -> "text " ^ s
  | Close c -> "close " ^ string_of_int c
  | Ping s -> "ping " ^ s
  | Pong s -> "pong " ^ s
  | Other o -> "opcode " ^ string_of_int o
