type 'a t = { encode : 'a -> Json.t; decode : Json.t -> ('a, string) result }

val int : int t
(** [`Int]. *)

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

val slot : Slot_value.t t
(** Encodes as [null]; decodes to an empty slot. *)

val result : 'a t -> 'e t -> ('a, 'e) result t
(** [Ok v] is [{"ok": v}] and [Error e] is [{"error": e}]. *)

val async : 'a t -> 'a Async.t t
(** On the server, a settled value is written inline:
    [{"$async":"aN","ok":v}] or [{"$async":"aN","error":"failed"}]. In a
    streaming render, a pending value is written as [{"$async":"aN"}] and
    the stream writes its value later, or [{"error":"failed"}] if it fails.
    A failure message goes to the [log_error] of [Yuka.Server.config] and never into the page,
    except for a [Server.Action.reject] message, which is sent. Outside a streaming render, a pending value is
    written as [{"$async":"aN","error":"pending at render"}]. Decoding a
    bare reference gives, after [render ~islands], the value that the page
    writes for that id; before it or outside the browser, a failed
    [Async]. *)

val encode : 'a t -> 'a -> Json.t
(** [encode c v] is [c.encode v]. *)

val decode : 'a t -> Json.t -> ('a, string) result
(** [decode c j] is [c.decode j]. The error names the expected kind and
    the start of the JSON text. *)
