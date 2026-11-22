module L = Yuka.Locale

let en = Messages.format Messages.En
let es = Messages.format Messages.Es
let iso = { en with L.date = "{year}-{mm}-{dd} {{x}} {other} {dd" }

let samples () =
  [ L.int en 0; L.int en 999; L.int en 1000; L.int en 1234567; L.int en (-1234567); L.int en (-2147483648);
    L.int es 1234567; L.int { en with L.group = "" } 1234567;
    L.float en ~digits:2 1234.5; L.float es ~digits:1 1234.5; L.float en ~digits:0 2.5; L.float en ~digits:0 (-2.5);
    L.float en ~digits:2 (-0.001); L.float en ~digits:3 0.1; L.float en ~digits:(-1) 9.99; L.float en ~digits:2 1.005;
    L.float en ~digits:2 1e15; L.float en ~digits:2 Float.nan; L.float en ~digits:2 Float.infinity;
    L.float en ~digits:2 Float.neg_infinity;
    L.date en ~year:2026 ~month:11 ~day:22; L.date es ~year:2026 ~month:11 ~day:22; L.date iso ~year:2026 ~month:1 ~day:5;
    L.month es 1; L.month es 13 ]

let expected =
  [ "0"; "999"; "1,000"; "1,234,567"; "-1,234,567"; "-2,147,483,648";
    "1.234.567"; "1234567";
    "1,234.50"; "1.234,5"; "3"; "-3";
    "0.00"; "0.100"; "10"; "1.00";
    "1,000,000,000,000,000.00"; "NaN"; {js|∞|js};
    {js|-∞|js};
    "November 22, 2026"; "22 de noviembre de 2026"; "2026-01-05 {x} {other} {dd";
    "enero"; "13" ]

let line locale =
  let f = Messages.format locale in
  L.float f ~digits:2 1234.5 ^ " | " ^ L.int f 98765 ^ " | " ^ L.date f ~year:2026 ~month:11 ~day:22
