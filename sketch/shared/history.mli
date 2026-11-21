(** Undo and redo of snapshots. The current value is kept by the caller. *)

type 'a t

val empty : 'a t

val record : ?limit:int -> 'a t -> before:'a -> 'a t
(** One step: [before] is the value before the change. It drops the redo
    steps and keeps at most [limit] undo steps (default 200). *)

val undo : 'a t -> current:'a -> ('a t * 'a) option
(** The value before the last step; [current] becomes a redo step. *)

val redo : 'a t -> current:'a -> ('a t * 'a) option
val can_undo : 'a t -> bool
val can_redo : 'a t -> bool
