let blocked = "about:blank#blocked"

let is_url_attribute = function
  | "href" | "src" | "action" | "formaction" | "xlink:href" | "xlinkHref" | "poster" | "cite" | "data"
  | "background" | "longdesc" | "manifest" | "codebase" | "icon" ->
      true
  | _ -> false

let safe_images = [ "png"; "gif"; "jpeg"; "jpg"; "webp"; "avif"; "bmp" ]

let unsafe value =
  let n = String.length value in
  let b = Buffer.create 24 in
  let i = ref 0 in
  while !i < n && value.[!i] <= ' ' do
    incr i
  done;
  while !i < n && Buffer.length b < 24 do
    (match value.[!i] with '\t' | '\n' | '\r' -> () | c -> Buffer.add_char b (Char.lowercase_ascii c));
    incr i
  done;
  let s = Buffer.contents b in
  let starts p = String.starts_with ~prefix:p s in
  starts "javascript:" || starts "vbscript:"
  || starts "data:"
     && not
          (List.exists
             (fun t -> starts ("data:image/" ^ t ^ ";") || starts ("data:image/" ^ t ^ ","))
             safe_images)
