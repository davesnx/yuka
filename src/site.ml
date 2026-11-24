let base () =
  if Host.in_browser then Host.base ()
  else match !(Types.current_session ()) with Some { context = Some c; _ } -> c.base | _ -> !Types.config_base

let join base path =
  let n = String.length path in
  if base = "" || n = 0 || String.unsafe_get path 0 <> '/' || (n > 1 && String.unsafe_get path 1 = '/') then path
  else if n = 1 || String.unsafe_get path 1 = '?' || String.unsafe_get path 1 = '#' then base ^ String.sub path 1 (n - 1)
  else base ^ path

let url path = join (base ()) path

let strip base target =
  let n = String.length base and m = String.length target in
  if n = 0 then Some target
  else if m < n || not (String.equal (String.sub target 0 n) base) then None
  else if m = n then Some "/"
  else
    match String.unsafe_get target n with
    | '/' -> Some (String.sub target n (m - n))
    | '?' | '#' -> Some ("/" ^ String.sub target n (m - n))
    | _ -> None
