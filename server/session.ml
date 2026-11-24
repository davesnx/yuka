type t = { secret : string; secure : bool; lifetime : float; max_lifetime : float; cookie : string }

let longest = 1e12

let make ?(secure = false) ?(lifetime = 14. *. 86400.) ?max_lifetime ~secret () =
  if String.length secret < 32 then invalid_arg "Yuka_server.sessions: the secret must have at least 32 bytes";
  if not (Float.is_finite lifetime && lifetime > 0. && lifetime <= longest) then
    invalid_arg "Yuka_server.sessions: the lifetime must be a positive number of seconds, at most 1e12";
  let max_lifetime = Option.value max_lifetime ~default:(Float.max lifetime (30. *. 86400.)) in
  if not (Float.is_finite max_lifetime && max_lifetime >= lifetime && max_lifetime <= longest) then
    invalid_arg "Yuka_server.sessions: max_lifetime must be a number of seconds from lifetime to 1e12";
  { secret; secure; lifetime; max_lifetime; cookie = (if secure then "__Host-yuka-session" else "yuka-session") }

let token_lifetime = 3600.

let hex bytes =
  String.concat "" (List.init (String.length bytes) (fun i -> Printf.sprintf "%02x" (Char.code bytes.[i])))

let random_hex n = hex (Mirage_crypto_rng_unix.getrandom n)
let mac t parts = Digestif.SHA256.(to_hex (hmac_string ~key:t.secret (String.concat "\n" parts)))
let is_hex s = String.for_all (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false) s
let is_digits s = s <> "" && String.length s <= 15 && String.for_all (function '0' .. '9' -> true | _ -> false) s

let signed t parts given =
  String.length given = 64 && is_hex given
  &&
  match Digestif.SHA256.of_hex_opt given with
  | Some given -> Digestif.SHA256.equal (Digestif.SHA256.hmac_string ~key:t.secret (String.concat "\n" parts)) given
  | None -> false

let seconds f = Printf.sprintf "%.0f" (Float.round f)

let left t ~issued ~now = Float.min t.lifetime (issued +. t.max_lifetime -. now)

let set_cookie t ~id ~issued ~now =
  let issued_text = seconds issued and max_age = left t ~issued ~now in
  let expires = seconds (now +. max_age) in
  let value = String.concat "." [ "v2"; id; issued_text; expires; mac t [ "yuka-session"; id; issued_text; expires ] ] in
  match Yuka.Server.Cookie.set ~max_age:(int_of_float (Float.round max_age)) ~secure:t.secure t.cookie value with
  | Ok (_, header) -> header
  | Error message -> invalid_arg message

type valid = { valid_id : string; issued : float; renew : bool }

let check t ~now value =
  match String.split_on_char '.' value with
  | [ "v2"; id; issued_text; expires; given ]
    when String.length id = 36 && is_hex id && is_digits issued_text && is_digits expires ->
      let at = float_of_string expires and issued = float_of_string issued_text in
      if at > now && issued +. t.max_lifetime > now && signed t [ "yuka-session"; id; issued_text; expires ] given then
        Some { valid_id = id; issued; renew = at -. now < t.lifetime /. 2. && Float.round (now +. left t ~issued ~now) > at }
      else None
  | _ -> None

let cookies header =
  List.filter_map
    (fun pair ->
      match String.index_opt pair '=' with
      | Some i -> Some (String.trim (String.sub pair 0 i), String.trim (String.sub pair (i + 1) (String.length pair - i - 1)))
      | None -> None)
    (String.split_on_char ';' header)

type found = { id : string; set_cookie : string option }

let find t ~now cookie_header =
  let values =
    match cookie_header with
    | None -> []
    | Some header -> List.filter_map (fun (n, v) -> if n = t.cookie then Some v else None) (cookies header)
  in
  let fresh id ~issued = { id; set_cookie = Some (set_cookie t ~id ~issued ~now) } in
  match List.find_map (check t ~now) values with
  | Some { valid_id; renew = false; _ } -> { id = valid_id; set_cookie = None }
  | Some { valid_id; issued; renew = true } -> fresh valid_id ~issued
  | None -> fresh (random_hex 18) ~issued:now

let token t ~id ~now =
  let expires = seconds (now +. Float.min token_lifetime t.lifetime) and nonce = random_hex 8 in
  String.concat "." [ "v1"; expires; nonce; mac t [ "yuka-csrf"; id; expires; nonce ] ]

let verify t ~id ~now token =
  match String.split_on_char '.' token with
  | [ "v1"; expires; nonce; given ] when is_digits expires && String.length nonce = 16 && is_hex nonce ->
      float_of_string expires > now && signed t [ "yuka-csrf"; id; expires; nonce ] given
  | _ -> false

let cookie_mac t ~name value = mac t [ "yuka-cookie"; name; value ]

let signed_cookie t ?max_age ?path ?domain ?same_site ?secure ?http_only name value =
  Yuka.Server.Cookie.set ?max_age ?path ?domain ?same_site ?secure ?http_only name
    (value ^ "." ^ cookie_mac t ~name value)

let verified_cookie t request name =
  Option.bind (Yuka.Server.Cookie.get request name) (fun text ->
      Option.bind (String.rindex_opt text '.') (fun i ->
          let value = String.sub text 0 i in
          if signed t [ "yuka-cookie"; name; value ] (String.sub text (i + 1) (String.length text - i - 1)) then Some value
          else None))
