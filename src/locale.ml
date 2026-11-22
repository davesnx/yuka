type t = { decimal : string; group : string; months : string array; date : string }

let grouped t digits =
  let n = String.length digits in
  let rec go i acc =
    if i <= 3 then String.sub digits 0 i ^ acc else go (i - 3) (t.group ^ String.sub digits (i - 3) 3 ^ acc)
  in
  go n ""

let int t n =
  let s = Int.to_string n in
  if n < 0 then "-" ^ grouped t (String.sub s 1 (String.length s - 1)) else grouped t s

let rec power p k = if k <= 0 then p else power (p *. 10.) (k - 1)

let rec digits_of y acc =
  if y < 1. then if acc = "" then "0" else acc
  else
    let d = Float.rem y 10. in
    digits_of ((y -. d) /. 10.) (Int.to_string (int_of_float d) ^ acc)

let rec zeros k s = if String.length s >= k then s else zeros k ("0" ^ s)

let float t ~digits x =
  if x <> x then "NaN"
  else if x = Float.infinity then {js|∞|js}
  else if x = Float.neg_infinity then {js|-∞|js}
  else
    let digits = if digits < 0 then 0 else if digits > 20 then 20 else digits in
    let y = Float.abs x *. power 1. digits in
    let r = Float.floor y in
    let r = if y -. r >= 0.5 then r +. 1. else r in
    let s = zeros (digits + 1) (digits_of r "") in
    let whole = String.length s - digits in
    let text =
      grouped t (String.sub s 0 whole) ^ if digits = 0 then "" else t.decimal ^ String.sub s whole digits
    in
    if x < 0. && r > 0. then "-" ^ text else text

let month t m = if m >= 1 && m <= Array.length t.months then t.months.(m - 1) else Int.to_string m
let two n = zeros 2 (Int.to_string n)

let date t ~year ~month:m ~day =
  let p = t.date in
  let n = String.length p in
  let rec close i = if i >= n then None else if p.[i] = '}' then Some i else close (i + 1) in
  let rec go i start acc =
    let text () = acc ^ String.sub p start (i - start) in
    if i >= n then text ()
    else
      match p.[i] with
      | '{' when i + 1 < n && p.[i + 1] = '{' -> go (i + 2) (i + 2) (text () ^ "{")
      | '}' when i + 1 < n && p.[i + 1] = '}' -> go (i + 2) (i + 2) (text () ^ "}")
      | '{' -> (
          match close (i + 1) with
          | None -> go n start acc
          | Some e -> (
              let field =
                match String.sub p (i + 1) (e - i - 1) with
                | "year" -> Some (Int.to_string year)
                | "month" -> Some (month t m)
                | "mm" -> Some (two m)
                | "day" -> Some (Int.to_string day)
                | "dd" -> Some (two day)
                | _ -> None
              in
              match field with Some v -> go (e + 1) (e + 1) (text () ^ v) | None -> go (e + 1) start acc))
      | _ -> go (i + 1) start acc
  in
  go 0 0 ""
