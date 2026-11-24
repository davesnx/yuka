let valid_name name =
  name <> ""
  && String.for_all
       (function
         | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_'
         | '`' | '|' | '~' ->
             true
         | _ -> false)
       name

let valid_path path =
  path <> "" && path.[0] = '/' && not (String.exists (fun c -> c = ';' || Char.code c < 32 || Char.code c = 127) path)

let valid_domain domain =
  domain <> "" && String.for_all (function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' -> true | _ -> false) domain

let header ~who ?max_age ~path ?domain ~(same_site : [ `Lax | `Strict | `None ]) ~secure ~http_only name value =
  let attribute = function Some text -> "; " ^ text | None -> "" in
  if not (valid_name name) then Error (who ^ ": invalid cookie name " ^ name)
  else if not (valid_path path) then Error (who ^ ": invalid path " ^ path)
  else
    match (domain, Web.encode_cookie_value value) with
    | Some domain, _ when not (valid_domain domain) -> Error (who ^ ": invalid domain " ^ domain)
    | _, None -> Error (who ^ ": invalid value, not valid " ^ if Web.in_browser then "UTF-16" else "UTF-8")
    | _, Some encoded ->
        Ok
          (name ^ "=" ^ encoded ^ "; Path=" ^ path
          ^ attribute (Option.map (fun domain -> "Domain=" ^ domain) domain)
          ^ attribute (Option.map (fun seconds -> "Max-Age=" ^ string_of_int seconds) max_age)
          ^ (if http_only then "; HttpOnly" else "")
          ^ (match same_site with `Lax -> "; SameSite=Lax" | `Strict -> "; SameSite=Strict" | `None -> "; SameSite=None")
          ^ if secure then "; Secure" else "")

let prefixed prefix name =
  String.length name >= String.length prefix
  && String.lowercase_ascii (String.sub name 0 (String.length prefix)) = prefix

let make ~who ?max_age ?(path = "/") ?domain ?(same_site = `Lax) ?(secure = false) ?(http_only = true) name value =
  match header ~who ?max_age ~path ?domain ~same_site ~secure ~http_only name value with
  | Error _ as e -> e
  | Ok _ when same_site = `None && not secure -> Error (who ^ ": SameSite=None needs ~secure:true")
  | Ok _ when prefixed "__host-" name && not (secure && path = "/" && domain = None) ->
      Error (who ^ ": a __Host- cookie needs ~secure:true, the path / and no domain")
  | Ok _ when prefixed "__secure-" name && not secure -> Error (who ^ ": a __Secure- cookie needs ~secure:true")
  | Ok h -> Ok ("set-cookie", h)

let set = make ~who:"Yuka.Server.Cookie.set"

let drop ?path ?domain name =
  make ~who:"Yuka.Server.Cookie.drop" ~max_age:0 ?path ?domain ~secure:(prefixed "__host-" name || prefixed "__secure-" name) name ""
