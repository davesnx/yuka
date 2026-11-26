(* Graphs in braille, as btop draws them: a character is two columns of four dots,
   so a line of [width] characters shows [2 * width] values, and [height] lines
   show [4 * height] levels. The characters are written {js|...|js} so Melange makes
   JavaScript strings of the characters. *)

(* [up.((left * 5) + right)]: [left] and [right] dots from the bottom. *)
let up =
  [|
    {js|⠀|js}; {js|⢀|js}; {js|⢠|js}; {js|⢰|js}; {js|⢸|js};
    {js|⡀|js}; {js|⣀|js}; {js|⣠|js}; {js|⣰|js}; {js|⣸|js};
    {js|⡄|js}; {js|⣄|js}; {js|⣤|js}; {js|⣴|js}; {js|⣼|js};
    {js|⡆|js}; {js|⣆|js}; {js|⣦|js}; {js|⣶|js}; {js|⣾|js};
    {js|⡇|js}; {js|⣇|js}; {js|⣧|js}; {js|⣷|js}; {js|⣿|js};
  |]

(* The same, with the dots from the top, for a graph that hangs down. *)
let down =
  [|
    {js|⠀|js}; {js|⠈|js}; {js|⠘|js}; {js|⠸|js}; {js|⢸|js};
    {js|⠁|js}; {js|⠉|js}; {js|⠙|js}; {js|⠹|js}; {js|⢹|js};
    {js|⠃|js}; {js|⠋|js}; {js|⠛|js}; {js|⠻|js}; {js|⢻|js};
    {js|⠇|js}; {js|⠏|js}; {js|⠟|js}; {js|⠿|js}; {js|⢿|js};
    {js|⡇|js}; {js|⡏|js}; {js|⡟|js}; {js|⡿|js}; {js|⣿|js};
  |]

let clamp low high x = if x < low then low else if x > high then high else x

(* The lines of a graph of [values] between 0 and [top], the top line first. A value
   above 0 shows at least one dot. With [~hang:true] the graph hangs from the top
   line, as the upload of btop. *)
let lines ?(hang = false) ~height ~top values =
  let n = Array.length values in
  let width = (n + 1) / 2 in
  let value i =
    let j = i - ((2 * width) - n) in
    if j < 0 then 0 else values.(j)
  in
  let dots = height * 4 in
  let level v =
    if v <= 0 || top <= 0 then 0 else clamp 1 dots (((v * dots) + (top / 2)) / top)
  in
  let levels = Array.init (2 * width) (fun i -> level (value i)) in
  List.init height (fun line ->
      (* The dots below this line (or above, for a graph that hangs). *)
      let under = if hang then line * 4 else (height - 1 - line) * 4 in
      let cell v = clamp 0 4 (v - under) in
      let table = if hang then down else up in
      String.concat ""
        (List.init width (fun c -> table.((cell levels.(2 * c) * 5) + cell levels.((2 * c) + 1)))))

(* A meter of [width] squares, [filled] of them on. *)
let meter ~width ~value ~top =
  let on = if top <= 0 then 0 else clamp 0 width (((value * width) + (top / 2)) / top) in
  (on, width - on)

let squares n = String.concat "" (List.init n (fun _ -> {js|■|js}))
