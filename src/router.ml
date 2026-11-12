let encode text =
  let b = Buffer.create (String.length text) in
  String.iter
    (function
      | ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~') as c ->
          Buffer.add_char b c
      | c ->
          let hex = "0123456789ABCDEF" and n = Char.code c in
          Buffer.add_char b '%';
          Buffer.add_char b hex.[n lsr 4];
          Buffer.add_char b hex.[n land 15])
    text;
  Buffer.contents b

let hex = function
  | '0' .. '9' as c -> Some (Char.code c - 48)
  | 'a' .. 'f' as c -> Some (Char.code c - 87)
  | 'A' .. 'F' as c -> Some (Char.code c - 55)
  | _ -> None

let decode ~plus text =
  let n = String.length text in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    (match text.[!i] with
    | '%' when !i + 2 < n -> (
        match (hex text.[!i + 1], hex text.[!i + 2]) with
        | Some h, Some l ->
            Buffer.add_char b (Char.chr ((h * 16) + l));
            i := !i + 2
        | _ -> Buffer.add_char b '%')
    | '+' when plus -> Buffer.add_char b ' '
    | c -> Buffer.add_char b c);
    incr i
  done;
  Buffer.contents b

let segment text =
  if text = "" || text = "." || text = ".." then
    invalid_arg "Yuka.Router.segment: empty, . or .. cannot be a path segment";
  encode text

let segments parts =
  match parts with
  | [] -> invalid_arg "Yuka.Router.segments: a catch-all needs one segment"
  | _ -> String.concat "" (List.map (fun p -> "/" ^ segment p) parts)

let int_param text =
  match int_of_string_opt text with
  | Some n when string_of_int n = text -> Some n
  | _ -> None

let search (query : (string * string) list) (key : string) =
  List.filter_map (fun (k, v) -> if k = key then Some v else None) query

type meth =
  [ `GET | `HEAD | `POST | `PUT | `PATCH | `DELETE | `OPTIONS | `Other of string ]

type 'r lookup =
  | Found of 'r
  | Wrong_method of meth list
  | Redirect of { permanent : bool; location : string }
  | Missing

let cut text c =
  match String.index_opt text c with
  | Some i -> (String.sub text 0 i, Some (String.sub text (i + 1) (String.length text - i - 1)))
  | None -> (text, None)

let split_target target =
  let target, _ = cut target '#' in
  cut target '?'

let split_path p =
  List.filter (fun x -> x <> "") (String.split_on_char '/' p)

let query target =
  match split_target target with
  | _, None | _, Some "" -> []
  | _, Some q ->
      List.filter_map
        (fun pair ->
          if pair = "" then None
          else
            let k, v = cut pair '=' in
            Some
              ( decode ~plus:true k,
                decode ~plus:true (Option.value v ~default:"") ))
        (String.split_on_char '&' q)
