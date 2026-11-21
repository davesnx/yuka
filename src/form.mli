(** Forms that post with no JavaScript and submit through {!Action.call}
    in an island. [[@@deriving form]] on a record [t] writes the field
    type [field], a polymorphic variant with one tag per record field
    ([title] gives [`Title]), the function [field_name] and the value
    [form : (t, field) Yuka.Form.t] (for a record [issue]: [issue_field],
    [issue_field_name] and [issue_form]); the same decoder runs on the server and
    in the browser. *)

type 'f errors = ('f option * string) list
(** [None] is an error for the whole form. *)

type 'a field_kind = 'a Form_core.field_kind
(** How one field reads from the posted strings and writes back. *)

val string : string field_kind
(** The first value; ["Missing"] when the field is absent. *)

val int : int field_kind
(** ["Not a whole number"] when it does not parse. *)

val float : float field_kind
val bool : bool field_kind
(** A checkbox: present is [true], absent is [false]. *)

val option : 'a field_kind -> 'a option field_kind
(** Absent or empty is [None]. *)

val list : 'a field_kind -> 'a list field_kind
(** Every value of the field, in order. *)

val custom : (string -> 'a option) -> ('a -> string) -> 'a field_kind
(** ["Not valid"] when [of_string] gives [None]. *)

val check : 'a field_kind -> ('a -> (unit, string) result) -> 'a field_kind
(** [check kind f] reads as [kind], then gives the [Error message] of
    [f value]. [[@check f]] on a field of a [[@@deriving form]] record
    adds it: the check runs where the form decodes, in the browser and on
    the server, so both give the same message. *)

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
    fields; the answer is [Ok (Ok output)] or [Ok (Error field_errors)].
    Fields that do not decode on the server, as a failed [[@check]], also
    give [Ok (Error field_errors)]. *)

type ('o, 'f) form
(** What the children of {!make} get. *)

val value : ('o, 'f) form -> 'f -> string
(** The value sent for the field when the page answers a failed post
    (422), else [""]. *)

val errors : ('o, 'f) form -> 'f errors State.read
(** The errors of the last submit, or of a failed post (422). Read it with
    {!State.get} in markup, and pass the value to {!field_error} or
    {!form_errors}. *)

val field_error : 'f errors -> 'f -> string option
(** The first error of the field. *)

val field_error_view : ('o, 'f) form -> 'f -> (id:string -> string -> 'k Kind.element) -> 'k Kind.element
(** A hole: [view ~id message] for the field's error, or nothing. Give the
    element of the error this [id]: each [input], [select] and [textarea] of
    the form whose [name] is the field gets [aria-invalid="true"] and an
    [aria-describedby] that holds [id], after the ids it already had, for as
    long as the field has an error; the server prints them on a failed post
    (422). When the error goes, Yuka removes [aria-invalid] and [id] only
    from the fields whose [aria-describedby] holds [id]: an [aria-invalid]
    that the author set on another field stays. The [id] is made from the
    action name, the [key] of {!make} and the field name. *)

val form_errors : 'f errors -> string list
(** The errors for the whole form, not for one field. *)

val form_errors_view : ('o, 'f) form -> (string -> 'k Kind.element) -> 'k Kind.element
(** A [<div role="alert" tabindex="-1">] that holds the view of each error
    for the whole form, so that a screen reader reads them when they
    show. When a submit in the browser ends with errors for the whole form
    and no field takes the focus, the focus goes to this [div]; on a failed
    post (422) with no field errors, the server prints [autofocus] on it. *)

val pending : ('o, 'f) form -> bool State.read
(** True while an island submit waits for its answer. Read it with
    {!State.get} in markup; read in the component body, it renders the
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
    JavaScript. Two forms of one action on a page need different [key]s:
    after a failed post (422) only the form with the posted key shows the
    sent values and errors, and the error ids are made from the key. In a
    development build, the browser console shows an error when two forms
    on a page have the same action and key. In an island, they stay for the
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
    another origin is not followed: it shows as the form error
    ["protocol error: refused a redirect"], and in a development build the
    browser console shows its URL. In an island, when a field of the form
    loses the focus, the form decodes it and its errors replace the errors
    of that field, with no request and with no focus change. When the
    focus goes to a button, there is no such check: a new error above the
    button could move it before the click ends.

    A screen reader hears the field errors of a failed submit: when a
    submit in the browser ends with field errors, the focus goes to the
    first field with an error, in document order, and the server prints
    [autofocus] on that field on a failed post (422) when it has none. Each
    field with an error gets the attributes of {!field_error_view}. *)
