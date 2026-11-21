let pad digits s = String.make (max 0 (digits - String.length s)) '0' ^ s

let rec strip s =
  let n = String.length s in
  if n > 0 && s.[n - 1] = '0' then strip (String.sub s 0 (n - 1)) else s

let to_string ?(digits = 2) value =
  if not (Float.is_finite value) then "0"
  else
    let scale = 10. ** float_of_int digits in
    let scaled = Float.round (Float.abs value *. scale) in
    if scaled = 0. then "0"
    else
      let whole = Float.of_int (Float.to_int (scaled /. scale)) in
      let whole = if whole *. scale > scaled then whole -. 1. else whole in
      let frac = scaled -. (whole *. scale) in
      let sign = if value < 0. then "-" else "" in
      let digits_text = strip (pad digits (Int.to_string (Float.to_int frac))) in
      sign ^ Int.to_string (Float.to_int whole) ^ if digits_text = "" then "" else "." ^ digits_text

let clamp ~lo ~hi value = if value < lo then lo else if value > hi then hi else value
