(** Why a remote call failed. *)
type error =
  | Rejected of string
      (** The server refused the input ({!Server.Action.reject}, bad
          input). The message is for the user. *)
  | Forbidden  (** The origin check failed. *)
  | Not_found  (** Unknown action. *)
  | Server  (** The implementation raised or failed; the detail is in the server log. *)
  | Network of string  (** No answer: offline, aborted, timeout. *)
  | Protocol of string  (** The answer did not decode. *)

(** The state of data that loads. [Loading (Some x)]: a new load runs and
    [x] is the last good data. *)
type 'a t =
  | Idle  (** Not enabled. *)
  | Loading of 'a option  (** A request runs; the option is the last good data. *)
  | Ready of { data : 'a; stale : bool }  (** [stale] is [false] for remote data. *)
  | Failed of { error : error; last : 'a option }

val data : 'a t -> 'a option
(** [data] of [Ready], [last] of [Failed], the option of [Loading]. *)

val map : ('a -> 'b) -> 'a t -> 'b t

val error_to_string : error -> string
(** [Rejected m] is [m]; the others are short English text. *)

val error_codec : error Codec.t
(** [{"kind": "rejected", "message": m}], [{"kind": "server"}], ... *)
