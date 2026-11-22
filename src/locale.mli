(** Number and date formats of a locale, the same on the server and in the
    browser. The functions are OCaml code on both targets, not [Intl], so
    the text that the server prints is the text that an island prints, and
    the island does not show a hydration mismatch. A page that does not
    call these functions loads none of their code. *)

type t = {
  decimal : string;  (** The decimal separator, as [","] in [1,5]. *)
  group : string;
      (** The separator of each group of three digits, as [","] in
          [1,234]. [""] gives no groups. *)
  months : string array;  (** The 12 month names, January first. *)
  date : string;
      (** The pattern of {!date}: [{year}], [{month}] (the name), [{mm}]
          (the number, two digits), [{day}] and [{dd}] (two digits). Write
          [{{] and [}}] for the characters [{] and [}]. Other text stays as
          it is. *)
}

val int : t -> int -> string
(** [int t 1234567] is ["1,234,567"] when [t.group] is [","]. *)

val float : t -> digits:int -> float -> string
(** [float t ~digits:2 1234.5] is ["1,234.50"] when [t.group] is [","]
    and [t.decimal] is ["."]: exactly [digits] digits after the separator,
    rounded half away from zero. [digits] below 0 is 0 and above 20 is 20.
    A value that rounds to 0 has no minus sign. NaN is ["NaN"], and the
    infinities are ["∞"] and ["-∞"]. The digits are exact up to 2{^53}
    for the value times 10{^digits}. *)

val month : t -> int -> string
(** [month t 1] is [t.months.(0)]. A month with no name in [t.months] is
    its number. *)

val date : t -> year:int -> month:int -> day:int -> string
(** [date t ~year:2026 ~month:11 ~day:22] fills [t.date]. The fields are
    calendar fields, not a time: give the island the same fields as the
    server, so that the time zone of the browser does not change the
    date. *)
