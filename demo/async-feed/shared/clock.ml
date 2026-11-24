let months = [| "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec" |]

let civil days =
  let z = days + 719468 in
  let era = (if z >= 0 then z else z - 146096) / 146097 in
  let doe = z - (era * 146097) in
  let yoe = (doe - (doe / 1460) + (doe / 36524) - (doe / 146096)) / 365 in
  let doy = doe - ((365 * yoe) + (yoe / 4) - (yoe / 100)) in
  let mp = ((5 * doy) + 2) / 153 in
  let day = doy - (((153 * mp) + 2) / 5) + 1 in
  let month = if mp < 10 then mp + 3 else mp - 9 in
  ((yoe + (era * 400) + if month <= 2 then 1 else 0), month, day)

let split time =
  let days = if time >= 0 then time / 86400 else ((time + 1) / 86400) - 1 in
  let seconds = time - (days * 86400) in
  let year, month, day = civil days in
  (year, month, day, seconds / 3600, seconds / 60 mod 60, seconds mod 60)

let iso time =
  let year, month, day, hour, minute, second = split time in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" year month day hour minute second

let utc time =
  let year, month, day, hour, minute, second = split time in
  Printf.sprintf "%s %d, %d, %02d:%02d:%02d UTC" months.(month - 1) day year hour minute second

let utc_day time =
  let _, month, day, _, _, _ = split time in
  Printf.sprintf "%d %s" day months.(month - 1)

let utc_clock time =
  let _, _, _, hour, minute, second = split time in
  Printf.sprintf "%d:%02d:%02d" hour minute second
