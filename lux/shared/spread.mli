(** Light that spreads from card to card on a square grid.

    Each card lit at level [n] tries each of its 8 neighbours that is still
    dark once, and lights it with probability {!probability}[ n]. The new card
    takes level [n + 1] and the style of the card that lit it. One {!step}
    lights one level. Only the cards lit by the last step are kept for the
    next one, so a step costs time in proportion to the cards it lights. *)

type t

val styles : int
(** The number of styles, and of seeds that {!create} places: 5. *)

val probability : int -> float
(** [3/5] for levels 1 and 2, [5/6] from level 3. *)

val create : ?size:int -> seed:int -> cols:int -> rows:int -> unit -> t
(** A grid of [size] x [size] cards (default 1024) with {!styles} seeds, one
    of each style, at random cells of a view of [cols] x [rows] cards at the
    centre of the grid. The seeds keep 3 cards from the edge of the view
    when the view is large enough. [seed] makes the run repeatable. Raises
    [Invalid_argument] when [size] is less than 3. *)

val of_seeds : ?size:int -> ?level:int -> seed:int -> (int * int * int) list -> (t, string) result
(** A grid with these lit cards, each [(x, y, style)], at [level] (default
    1). [Error] for a card outside the grid, a style outside
    [0 .. styles - 1], the same cell twice, no card, or [level < 1]. *)

val size : t -> int
val level : t -> int
(** The level of the cards lit last. *)

val step : t -> bool
(** Lights the next level. [false] when it lit no card: then the light has
    stopped, {!finished} is [true] and the level stays. *)

val fresh_count : t -> int
(** The number of cards lit by the last step (the seeds before the first). *)

val fresh : t -> int -> int
(** [fresh t i], for [0 <= i < fresh_count t]: the cell [y * size + x] of
    the [i]th card lit by the last step. *)

val style : t -> int -> int option
(** The style of the card at cell [y * size + x]; [None] when dark or
    outside the grid. *)

val lit_count : t -> int
val finished : t -> bool
(** No card was lit by the last step. *)

val bounds : t -> int * int * int * int
(** [(min_x, min_y, max_x, max_y)] of the lit cards, inclusive. *)
