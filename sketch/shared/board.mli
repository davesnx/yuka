(** The shapes of a board, back to front, and the next free id. *)

type t = private { shapes : Shape.t array; next_id : int }

val empty : t
val shapes : t -> Shape.t array
val length : t -> int
val find : t -> int -> Shape.t option
val mem : t -> int -> bool

val fresh_id : t -> int * t
(** An id that no shape of the board has, and the board that will give the
    next one. *)

val add : t -> Shape.t -> t
(** Puts the shape in front. A shape with the same id leaves the board. *)

val replace : t -> Shape.t list -> t
(** Puts each shape in the place of the shape with its id; ids that are
    not on the board are ignored. *)

val remove : t -> int list -> t
val to_front : t -> int list -> t
val to_back : t -> int list -> t

val insert_copies : t -> Shape.t list -> offset:Vec.t -> t * int list
(** Adds copies of the shapes with new ids, moved by [offset], in front,
    in their order; gives the new ids. *)

val top_hit : t -> tolerance:float -> Vec.t -> Shape.t option
(** The shape under the point: the front-most shape whose stroke or filled
    area is under it, else the smallest hollow shape around it. *)

val in_box : t -> Geom.Box.t -> int list
(** Ids of the shapes whose geometry touches the box, back to front. *)

val bounds : t -> int list -> Geom.Box.t option
(** The union of {!Shape.visual_bounds} of the shapes with these ids;
    [None] when none of them is on the board. *)

val all_bounds : t -> Geom.Box.t option

val to_json_text : t -> string
(** The board as JSON text, which {!of_json} reads back. *)

val of_json : Shape.metrics -> Yuka.Json.t -> (t, string) result
