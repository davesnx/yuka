type 'a t

val make : decode:(string -> 'a option) -> encode:('a -> string) -> 'a t
(** [decode] gets the text after percent-decoding. For a path param,
    [None] means the path does not match. For a search field, the value
    is dropped: an optional field gets [None], a field with a default
    gets the default, and a list field leaves the value out. [encode]
    must be the inverse of [decode]; [href] percent-encodes its result. *)

val int : int t
(** The form [string_of_int] writes: [01], [-0] and [+1] do not decode,
    so each value has one URL. *)

val string : string t
val bool : bool t
(** ["true"] and ["false"]. *)

val decode : 'a t -> string -> 'a option
val encode : 'a t -> 'a -> string
