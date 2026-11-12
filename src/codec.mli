type 'a t = private { encode : 'a -> Json.t; decode : Json.t -> ('a, string) result }

val make : encode:('a -> Json.t) -> decode:(Json.t -> ('a, string) result) -> 'a t

val map : ('a -> 'b) -> ('b -> 'a) -> 'a t -> 'b t
(** [map of_a to_a c]: a codec of ['b] that writes [to_a b] with [c] and
    reads with [c], then applies [of_a]. *)

val int : int t
(** [`Int], or a [`Float] with an integral value in the [int] range of
    the platform (see [Yuka.Json.of_string]). *)

val float : float t
(** Decoding accepts [`Int] too. *)

val string : string t
(** [`String]. *)

val bool : bool t
(** [`Bool]. *)

val unit : unit t
(** [`Null]. *)

val list : 'a t -> 'a list t
(** [`List]. Decoding stops at the first element that fails. *)

val array : 'a t -> 'a array t
(** As [list]. *)

val option : 'a t -> 'a option t
(** [None] is [`Null]. *)

val result : 'a t -> 'e t -> ('a, 'e) result t
(** [Ok v] is [{"ok": v}] and [Error e] is [{"error": e}]. *)

val async : 'a t -> 'a Async.t t
(** On the server, a settled value is written inline:
    [{"$async":"aN","ok":v}] or [{"$async":"aN","error":"server error"}].
    In a streaming render, a pending value is written as [{"$async":"aN"}]
    and the stream writes its value later, or [{"error":"server error"}] if
    it fails. A failure message goes to the [log_error] of
    [Yuka.Server.config] and never into the page, except for a
    [Server.Action.reject] message, which is sent in place of
    ["server error"]. This is the rule of [Yuka.Await], so an [Await] in an
    island shows the same text before and after hydration. Outside a streaming render, a pending value is
    written as [{"$async":"aN","error":"pending at render"}]. Decoding a
    bare reference gives, after [render ~islands], the value that the page
    writes for that id; before it or outside the browser, a failed
    [Async]. *)

val encode : 'a t -> 'a -> Json.t
(** [encode codec value] is [codec.encode value]. *)

val decode : 'a t -> Json.t -> ('a, string) result
(** [decode codec json] is [codec.decode json]. The error of a codec of this module
    names the expected kind and the start of the JSON text. *)
