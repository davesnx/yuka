val lock : containers:string list -> unit -> unit -> unit
(** [lock ~containers ()] stops the page and each element of [containers]
    (CSS selectors) from scrolling, and returns the function that undoes it.
    Hiding a scrollbar gives its width back to the content, which then jumps
    sideways; so each one that hides gets the width of its scrollbar added to
    its right padding (to the [body] for the page). *)
