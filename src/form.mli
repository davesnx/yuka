(** Forms that post with no JavaScript and submit through {!Action.call}
    in an island. [[@@deriving form]] on a record writes the field type,
    the field names and a [('i, 'f) t]; the same decoder runs on the
    server and in the browser. *)

type 'f errors = ('f option * string) list
(** [None] is an error for the whole form. *)

type 'a kind
(** How one field reads from the posted strings and writes back. *)

val string : string kind
(** The first value; ["Missing"] when the field is absent. *)

val int : int kind
(** ["Not a whole number"] when it does not parse. *)

val float : float kind
val bool : bool kind
(** A checkbox: present is [true], absent is [false]. *)

val option : 'a kind -> 'a option kind
(** Absent or empty is [None]. *)

val list : 'a kind -> 'a list kind
(** Every value of the field, in order. *)

val custom : (string -> 'a option) -> ('a -> string) -> 'a kind
(** ["Not valid"] when [of_string] gives [None]. *)

type ('i, 'f) t
(** The fields of a form: decode, encode and names. *)

type ('i, 'o, 'f) action = ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t

type 'f decoding

val fields :
  names:('f * string) list ->
  decode:('f decoding -> ('i, 'f errors) result) ->
  encode:('i -> (string * string) list) ->
  ('i, 'f) t
(** Used by the code that [[@@deriving form]] writes. *)

val field : 'f decoding -> 'f -> string -> 'a kind -> 'a option
val get : 'a option -> 'a
val finish : 'f decoding -> (unit -> 'i) -> ('i, 'f errors) result
val put : string -> 'a kind -> 'a -> (string * string) list

val decode : ('i, 'f) t -> (string * string) list -> ('i, 'f errors) result
(** Every field error, in field order. *)

val encode : ('i, 'f) t -> 'i -> (string * string) list
val name : ('i, 'f) t -> 'f -> string

val action :
  name:string ->
  fields:('i, 'f) t ->
  output:'o Codec.t ->
  ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t
(** An action whose input is a form: {!Action.call} sends the encoded
    fields; the answer is [Ok o] or the field errors. *)

type ('o, 'f) form
(** What the children of {!make} get. *)

val value : ('o, 'f) form -> 'f -> string
(** The value sent for the field when the page answers a failed post
    (422), else [""]. *)

val error : ('o, 'f) form -> 'f -> string option
(** Tracked read of the first error of the field. *)

val error_view : ('o, 'f) form -> 'f -> (string -> 'k Kind.element) -> 'k Kind.element
(** A hole: the view of the field's error, or nothing. *)

val form_errors : ('o, 'f) form -> string list
val form_error_view : ('o, 'f) form -> (string -> 'k Kind.element) -> 'k Kind.element
(** The errors for the whole form. *)

val pending : ('o, 'f) form -> bool
(** Tracked: true while an island submit waits for its answer. Read it in
    a hole ([Yuka.hole]); read in the children directly, it renders the
    enclosing component again, with a new form. *)

val make :
  action:('i, ('o, 'f errors) result, [ `Mutation ]) Action.t ->
  ?key:string ->
  ?run:('i -> ('o, 'f errors) result Async.t) ->
  ?on_ok:('o -> unit) ->
  children:(('o, 'f) form -> 'k Kind.element) ->
  unit ->
  'k Kind.element
(** [<Yuka.Form action>(fun form -> ...)</Yuka.Form>]: a
    [<form method="post">] with no [action] attribute (it posts to the
    page URL) and a hidden [_yuka_action] field, so it works with no
    JavaScript. Give [key] to tell apart two forms of one action on a
    page: after a failed post (422) only the form with the posted key
    shows the sent values and errors. In an island, they stay for the
    life of that [<form>] element (a new render of the form shows them
    again) until a submit in the browser. In an island, a submit is handled
    in the browser: the fields (with the submit button's [name] and
    [value]) are decoded first (an error shows at once, with no request),
    then [run input] (default: the action call) runs while [pending] is
    true; field errors show, and on [Ok o] [on_ok o] runs, or else the page
    follows the server's [redirect] (with [run], the page URL) with a
    client navigation, as a post with no JavaScript does. A [redirect] to
    another origin is not followed: it shows as a form error. Raises
    [Invalid_argument] when [action] is not from {!val-action}. *)
