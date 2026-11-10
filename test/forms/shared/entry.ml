module Level = struct
  type t = Low | High

  let of_string = function "low" -> Some Low | "high" -> Some High | _ -> None
  let to_string = function Low -> "low" | High -> "high"
end

type entry = {
  title : string;
  count : int;
  ratio : float option;
  urgent : bool;
  level : Level.t;
  tags : string list;
}
[@@deriving form]

type note = { body : string } [@@deriving form]

let save = Yuka.Form.action ~name:"save_entry" ~fields:entry_form ~output:Yuka.Codec.string
let jot = Yuka.Form.action ~name:"jot" ~fields:note_form ~output:Yuka.Codec.int

let cases =
  [
    ( "valid",
      [ ("title", "a"); ("count", "3"); ("ratio", ""); ("urgent", "on"); ("level", "high"); ("tags", "x"); ("tags", "y") ] );
    ("errors", [ ("count", "x3"); ("ratio", "nope"); ("level", "mid"); ("tags", "z") ]);
    ("unchecked", [ ("title", ""); ("count", "-1"); ("ratio", "0.5"); ("level", "low") ]);
  ]

let show values =
  match Yuka.Form.decode entry_form values with
  | Ok e ->
      Printf.sprintf "ok %s %d %s %b %s [%s]" e.title e.count
        (match e.ratio with Some r -> string_of_float r | None -> "none")
        e.urgent (Level.to_string e.level) (String.concat "," e.tags)
  | Error errors ->
      "error "
      ^ String.concat "; "
          (List.map
             (fun (f, m) -> (match f with Some f -> entry_field_name f | None -> "form") ^ ": " ^ m)
             errors)

let expected =
  [
    "ok a 3 none true high [x,y]";
    "error title: Missing; count: Not a whole number; ratio: Not a number; level: Not valid";
    "ok  -1 0.5 false low []";
  ]
