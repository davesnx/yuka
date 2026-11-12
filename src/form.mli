(** Forms that post with no JavaScript and submit through {!Action.call}
    in an island. [[@@deriving form]] on a record [t] writes the field
    type [field], a polymorphic variant with one tag per record field
    ([title] gives [`Title]), the function [field_name] and the value
    [form : (t, field) Yuka.Form.t] (for a record [issue]: [issue_field],
    [issue_field_name] and [issue_form]); the same decoder runs on the server and
    in the browser. *)

type 'f errors = ('f option * string) list
(** [None] is an error for the whole form. *)

type 'a kind = 'a Form_core.kind
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

type ('i, 'f) t = ('i, 'f) Form_core.t
(** The fields of a form: decode, encode and names. *)

type ('i, 'o, 'f) action = ('i, ('o, 'f errors) result, [ `Form ]) Action.t
(** An action whose input is a form. Only {!val-action} makes one. *)

val decode : ('i, 'f) t -> (string * string) list -> ('i, 'f errors) result
(** Every field error, in field order. *)

val encode : ('i, 'f) t -> 'i -> (string * string) list
val name : ('i, 'f) t -> 'f -> string

val action : name:string -> fields:('i, 'f) t -> output:'o Codec.t -> ('i, 'o, 'f) action
(** An action whose input is a form: {!Action.call} sends the encoded
    fields; the answer is [Ok (Ok output)] or [Ok (Error field_errors)]. *)

type ('o, 'f) form
(** What the children of {!make} get. *)

val value : ('o, 'f) form -> 'f -> string
(** The value sent for the field when the page answers a failed post
    (422), else [""]. *)

val error : ('o, 'f) form -> 'f -> string option
(** Tracked read of the first error of the field. *)

val error_view : ('o, 'f) form -> 'f -> (string -> 'k Kind.element) -> 'k Kind.element
(** A hole: the view of the field's error, or nothing. *)

val errors : ('o, 'f) form -> string list
(** Tracked read of the errors for the whole form, not for one field. *)

val errors_view : ('o, 'f) form -> (string -> 'k Kind.element) -> 'k Kind.element
(** A hole: the view of each error of {!val-errors}. *)

val pending : ('o, 'f) form -> bool
(** Tracked: true while an island submit waits for its answer. Read it in
    a hole ([Yuka.hole]); read in the children directly, it renders the
    enclosing component again, with a new form. *)

val make :
  action:('i, 'o, 'f) action ->
  ?key:string ->
  ?run:('i -> (('o, 'f errors) result, Status.error) result Async.t) ->
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
    true; field errors show, an [Error error] shows as a form error with the
    text of {!Status.error_to_string}, and on [Ok output] [on_ok output] runs, or
    else the page
    follows the server's [redirect] (with [run], the page URL) with a
    client navigation, as a post with no JavaScript does. A [redirect] to
    another origin is not followed: it shows as a form error. *)
