val to_string : ?digits:int -> float -> string
(** The number rounded to [digits] decimals (default 2), with no trailing
    zeros and no exponent, as SVG and CSS read it: [12], [-3.5], [0.25].
    A value that is not finite gives ["0"]. *)

val clamp : lo:float -> hi:float -> float -> float
