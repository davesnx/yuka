type ('a, 'r) t
(** A path. ['a] is the type of the function that takes the parameters of the
    path, and ['r] is what that function returns. *)

val root : ('r, 'r) t
(** The path [/]. *)

val s : string -> ('r, 'r) t
(** A fixed segment. Raises [Invalid_argument] if the text is empty or holds
    a [/]. *)

val string : (string -> 'r, 'r) t
(** A segment taken as a string parameter. *)

val int : (int -> 'r, 'r) t
(** A segment taken as an int parameter. It matches an optional [-] and
    digits only. *)

val ( / ) : ('a, 'b) t -> ('b, 'c) t -> ('a, 'c) t
(** Joins two paths. [s "issue" / string] has type
    [(string -> 'r, 'r) t]. *)

val href : ?query:(string * string) list -> ('a, string) t -> 'a
(** [href path] is a function that takes the parameters and returns the URL.
    Parameters and query are percent-encoded. The URL starts with [/] and
    has no trailing slash, except [/] itself. *)

val parse : ('a, 'r) t -> 'a -> string -> 'r option
(** [parse path f target] matches a request target (path, with an optional
    query and fragment, which are ignored) against [path]. A trailing slash
    is ignored. Segments are percent-decoded. On a match it returns [f]
    applied to the parameters. *)

val query : string -> (string * string) list
(** The decoded query pairs of a request target ([+] is a space). *)

type 'r case
(** A path with the function that handles it. *)

val case : ('a, 'r) t -> 'a -> 'r case

val dispatch : 'r case list -> string -> 'r option
(** The result of the first case that matches the target. *)
