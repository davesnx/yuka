(* The story is one tree of scenes, built when the server starts. The browser only
   sees the scene it is on and the ids of its exits: an id is a digest of the place of
   the scene in the tree, so a URL tells nothing about where it leads.

   - The root is the opening. Each of the five acts starts with a title scene, then
     five riddles.
   - A riddle has one child per answer. The right answer leads to the next riddle (or
     to the next act, or to the duel after the last riddle). A wrong answer leads to a
     death: a leaf, whose exits go back up the tree.
   - The duel is a game of noughts and crosses against the Ash King. Its subtree has a
     child for each free cell: the cell the player takes, then the reply of the King.
     A won game is the end of the story. *)

type outcome = Won | Lost | Drawn

type view =
  | Opening
  | Act of { act : int }
  | Riddle of { act : int; number : int }
  | Death of { act : int; answer : string; line : string }
  | Duel of { board : Board.t; last : int option }
  | Ending of { board : Board.t; last : int option; outcome : outcome }

type exit = { label : string; target : string; up : bool }
(* [up] is a link back to an ancestor, not an edge of the tree. *)

type scene = {
  key : string;  (** The place in the tree: the exits taken from the root, as ["0.2.1"]. *)
  id : string;  (** What the URL shows. *)
  view : view;
  progress : int;  (** Riddles solved on the way here, 0 to 25. *)
  exits : exit list;  (** The children, in order, then the links up. *)
  children : scene list;
}

type riddle = { asker : string; prompt : string; answers : string list; right : int }
type act = { name : string; intro : string list; deaths : string list; riddles : riddle list }

let riddle asker prompt answers ~right = { asker; prompt; answers; right }

let acts =
  [|
    {
      name = "The Blighted Moor";
      intro =
        [
          "The village burned three nights ago. The ash has not stopped falling since.";
          "Somewhere beyond the moor, the Ash King waits on a throne of cinders.";
          "The road is guarded by those who ask, and remember every wrong answer.";
        ];
      deaths = [ "The moor drinks you down, one cold mouthful at a time."; "The crows are patient. They were right to be." ];
      riddles =
        [
          riddle "A gravedigger leans on his spade and does not look up."
            "What has roots nobody sees, is taller than trees, up and up it goes, and yet never grows?"
            [ "A shadow"; "A mountain"; "A cathedral spire" ] ~right:1;
          riddle "A blind woman blocks the bridge with her staff."
            "The more of me you take, the more of me you leave behind. What am I?"
            [ "Footsteps"; "Gold"; "Years" ] ~right:0;
          riddle "Something wet speaks from the bottom of a well."
            "I run but never walk. I have a mouth but never talk. What am I?"
            [ "A wolf"; "A ghost"; "A river" ] ~right:2;
          riddle "A cartographer, long dead, still guards his maps."
            "I have cities but no houses, forests but no trees, and water but no fish. What am I?"
            [ "A map"; "A dream"; "A painting" ] ~right:0;
          riddle "The last gate is a mouth carved in a standing stone."
            "What is broken as soon as you speak its name?"
            [ "An oath"; "Silence"; "A curse" ] ~right:1;
        ];
    };
    {
      name = "The Sunken Sands";
      intro =
        [
          "The moor gives way to a desert that swallowed a city whole.";
          "Its towers lean out of the dunes like the ribs of something enormous.";
          "The sand hisses with voices. All of them have questions.";
        ];
      deaths = [ "The dunes close over you without a sound."; "The sun takes its time with you." ];
      riddles =
        [
          riddle "A merchant sells water by the drop, and asks before he pours."
            "Alive without breath, cold as death, never thirsty, ever drinking, clad in mail, never clinking."
            [ "A knight's ghost"; "A fish"; "A serpent" ] ~right:1;
          riddle "The wind itself seems to ask this one."
            "Voiceless it cries, wingless it flutters, toothless it bites, mouthless it mutters."
            [ "Wind"; "A bat"; "Fire" ] ~right:0;
          riddle "A sphinx of cracked sandstone opens one eye."
            "What comes once in a minute, twice in a moment, but never in a thousand years?"
            [ "A heartbeat"; "An eclipse"; "The letter M" ] ~right:2;
          riddle "An undertaker measures you with his eyes."
            "The one who makes it sells it. The one who buys it never uses it. The one who uses it never sees it."
            [ "A crown"; "A coffin"; "A tomb key" ] ~right:1;
          riddle "Inside the buried palace, a brazier speaks."
            "I am always hungry and must always be fed. The finger I touch will soon turn red."
            [ "Fire"; "A demon"; "A leech" ] ~right:0;
        ];
    };
    {
      name = "The Drowned Jungle";
      intro =
        [
          "Past the desert the air turns thick and green, and the rivers run warm.";
          "Temples rot under the vines. Something in the water keeps pace with you.";
          "The trees here are older than kings, and far less forgiving.";
        ];
      deaths = [ "The river closes over your head. It is warmer than you hoped."; "The vines take you in, slowly, kindly." ];
      riddles =
        [
          riddle "A witch doctor rattles a string of tiny skulls."
            "A box without hinges, key or lid, yet golden treasure inside is hid."
            [ "A skull"; "A cocoon"; "An egg" ] ~right:2;
          riddle "An alchemist holds up a vial of something that moves."
            "What has a neck but no head, and wears a cap?"
            [ "A bottle"; "A scarecrow"; "A gallows" ] ~right:0;
          riddle "A stone idol speaks, and moss falls from its lips."
            "This thing all things devours: birds, beasts, trees, flowers. It gnaws iron and bites steel."
            [ "Rust"; "Time"; "Hunger" ] ~right:1;
          riddle "A drowned priest rises waist-deep from the marsh."
            "What gets wetter the more it dries?"
            [ "Salt"; "The tide"; "A towel" ] ~right:2;
          riddle "A tailor of the dead threads a needle of bone."
            "What has one eye but cannot see?"
            [ "A needle"; "A cyclops"; "An owl" ] ~right:0;
        ];
    };
    {
      name = "The Gates of Ember";
      intro =
        [
          "The jungle ends at a cliff, and the cliff ends at a sea of fire.";
          "A bridge of black glass crosses it. Every slab of it is warm.";
          "Demons keep the gates, and demons love a puzzle.";
        ];
      deaths = [ "The fire was quick. That is the only mercy here."; "You fall a long way, and the lava is waiting." ];
      riddles =
        [
          riddle "A horned ferryman steers a boat across the lava."
            "A rope ladder hangs off my boat, its rungs a foot apart. The lava rises two feet. How many rungs sink below it?"
            [ "Two more"; "None more"; "Four more" ] ~right:1;
          riddle "An imp grins, and counts on its claws."
            "Forward I am heavy, but backward I am not. What am I?"
            [ "A sword"; "A soul"; "A ton" ] ~right:2;
          riddle "A demon of smoke curls around your ankles."
            "What can fill a room but takes up no space?"
            [ "Light"; "Smoke"; "Fear" ] ~right:0;
          riddle "Two gatekeepers argue, then turn to you."
            "If two is company and three is a crowd, what are four and five?"
            [ "A horde"; "Seven"; "Nine" ] ~right:2;
          riddle "A coin-counting devil flips something golden."
            "I have a head and a tail, but no body. What am I?"
            [ "A coin"; "A worm"; "A scroll" ] ~right:0;
        ];
    };
    {
      name = "The Frost Summit";
      intro =
        [
          "Beyond the gates the fire burns out, and the world turns white.";
          "The mountain climbs into a sky the colour of old bone.";
          "At its summit, the Ash King has already set the board.";
        ];
      deaths = [ "The cold is gentle at the end. It sings you to sleep."; "The avalanche does not even notice you." ];
      riddles =
        [
          riddle "A frozen sentry blinks frost from its lashes."
            "What can you catch, but not throw?"
            [ "A spear"; "A cold"; "A falling star" ] ~right:1;
          riddle "A barbarian chieftain bars the pass with an axe."
            "Thirty white horses on a red hill. First they champ, then they stamp, then they stand still."
            [ "Teeth"; "Snowflakes"; "Pale riders" ] ~right:0;
          riddle "A wolf with a woman's voice circles you."
            "What has many teeth, but cannot bite?"
            [ "A frost giant"; "A wolf"; "A comb" ] ~right:2;
          riddle "An old hermit warms his hands over nothing."
            "What goes up, but never comes down?"
            [ "Smoke"; "Your age"; "A soul" ] ~right:1;
          riddle "The doors of the throne room ask the last riddle themselves."
            "The more there is of it, the less you see. What is it?"
            [ "Darkness"; "Gold"; "Ice" ] ~right:0;
        ];
    };
  |]

let riddles_per_act = 5
let riddle_count = Array.length acts * riddles_per_act

let duel_lines =
  [
    "The Ash King gestures at a board of nine runes, scorched into the stone between you.";
    "\"You play the frost runes,\" he says. \"I play the fire. Three in a row wins. Begin.\"";
  ]

(* The ids. A digest of the key, so they stay the same from one start to the next, and
   from one server to another. *)

let id_of key = String.sub (Digest.to_hex (Digest.string ("ashfall/" ^ key))) 0 12
let child key index = if key = "" then Int.to_string index else key ^ "." ^ Int.to_string index
let parent key = match String.rindex_opt key '.' with Some dot -> String.sub key 0 dot | None -> ""
let root_key = ""
let down label (scene : scene) = { label; target = scene.id; up = false }
let up label key = { label; target = id_of key; up = true }

let scene key view ~progress ~children ~exits = { key; id = id_of key; view; progress; exits; children }

let rec duel key ~start ~board ~last =
  let children =
    List.filter_map
      (fun cell ->
        if not (Board.free board cell) then None
        else
          let key = child key cell in
          let board = Board.play board cell Board.X in
          if Board.wins board Board.X then Some (cell, ending key ~start ~board ~last:None ~outcome:Won)
          else if Board.full board then Some (cell, ending key ~start ~board ~last:None ~outcome:Drawn)
          else
            let reply = Board.reply board in
            let board = Board.play board reply Board.O in
            (* The player moves first, so the board fills on a move of the player. *)
            if Board.wins board Board.O then Some (cell, ending key ~start ~board ~last:(Some reply) ~outcome:Lost)
            else Some (cell, duel key ~start ~board ~last:(Some reply)))
      (List.init 9 Fun.id)
  in
  scene key
    (Duel { board; last })
    ~progress:riddle_count ~children:(List.map snd children)
    ~exits:(List.map (fun (cell, scene) -> down (Int.to_string cell) scene) children)

and ending key ~start ~board ~last ~outcome =
  let exits =
    match outcome with
    | Won -> [ up "Begin a new tale" root_key ]
    | Lost | Drawn -> [ up "Challenge him again" start; up "Abandon the quest" root_key ]
  in
  scene key (Ending { board; last; outcome }) ~progress:riddle_count ~children:[] ~exits

let rec act_title key ~act =
  let first = riddle_scene (child key 0) ~act ~number:0 in
  scene key (Act { act }) ~progress:(act * riddles_per_act) ~children:[ first ] ~exits:[ down "Continue" first ]

and riddle_scene key ~act ~number =
  let { answers; right; _ } = List.nth acts.(act).riddles number in
  let progress = (act * riddles_per_act) + number in
  let wrong = ref (-1) in
  let children =
    List.mapi
      (fun index answer ->
        let key = child key index in
        if index = right then after key ~act ~number
        else begin
          incr wrong;
          let line = List.nth acts.(act).deaths (!wrong mod List.length acts.(act).deaths) in
          scene key
            (Death { act; answer; line })
            ~progress ~children:[]
            ~exits:[ up "Rise again" (parent key); up "Abandon the quest" root_key ]
        end)
      answers
  in
  scene key (Riddle { act; number }) ~progress ~children ~exits:(List.map2 down answers children)

and after key ~act ~number =
  if number + 1 < riddles_per_act then riddle_scene key ~act ~number:(number + 1)
  else if act + 1 < Array.length acts then act_title key ~act:(act + 1)
  else duel key ~start:key ~board:Board.empty ~last:None

let root =
  let first = act_title (child root_key 0) ~act:0 in
  scene root_key Opening ~progress:0 ~children:[ first ] ~exits:[ down "Enter the world" first ]

let scenes =
  let table = Hashtbl.create 1024 in
  let rec add scene =
    if Hashtbl.mem table scene.id then failwith ("Story: two scenes have the id " ^ scene.id);
    Hashtbl.add table scene.id scene;
    List.iter add scene.children
  in
  add root;
  table

let find id = Hashtbl.find_opt scenes id
let count () = Hashtbl.length scenes

(* The tree as the server sees it, for [quest_server --tree]. The duel is summed up: it
   has hundreds of positions. *)

let roman act = [| "I"; "II"; "III"; "IV"; "V" |].(act)

let describe scene =
  match scene.view with
  | Opening -> "Opening"
  | Act { act } -> Printf.sprintf "Act %s: %s" (roman act) acts.(act).name
  | Riddle { act; number } ->
      Printf.sprintf "Riddle %s.%d: %s" (roman act) (number + 1) (List.nth acts.(act).riddles number).prompt
  | Death { answer; _ } -> Printf.sprintf "Death (%S)" answer
  | Duel _ -> "Duel"
  | Ending { outcome = Won; _ } -> "Victory"
  | Ending { outcome = Lost; _ } -> "Defeat"
  | Ending { outcome = Drawn; _ } -> "Draw"

let rec size scene = List.fold_left (fun total child -> total + size child) 1 scene.children

let rec endings outcome scene =
  match scene.view with
  | Ending { outcome = found; _ } -> if found = outcome then 1 else 0
  | _ -> List.fold_left (fun total child -> total + endings outcome child) 0 scene.children

(* Each scene on its own line, then its leaves as branches, then the scene that goes on,
   at the same indent: the tree reads as the path through it. *)
let outline () =
  let buffer = Buffer.create 8192 in
  let rec go scene =
    (match scene.view with
    | Duel _ ->
        Printf.bprintf buffer "%s: %d positions; %d victories, %d defeats, %d draws  [%s]\n" (describe scene) (size scene)
          (endings Won scene) (endings Lost scene) (endings Drawn scene) scene.id
    | _ -> Printf.bprintf buffer "%s  [%s]\n" (describe scene) scene.id);
    match scene.view with
    | Duel _ -> ()
    | _ ->
        let edges = List.combine (List.filteri (fun index _ -> index < List.length scene.children) scene.exits) scene.children in
        let leaves, rest = List.partition (fun (_, child) -> child.children = []) edges in
        let count = List.length edges in
        List.iteri
          (fun index ((exit : exit), child) ->
            Printf.bprintf buffer "%s %S -> %s  [%s]\n"
              (if index = count - 1 then "└─" else "├─")
              exit.label
              (match child.view with Death _ -> "death" | _ -> describe child)
              child.id)
          leaves;
        List.iteri
          (fun index ((exit : exit), child) ->
            Printf.bprintf buffer "%s %S\n" (if List.length leaves + index = count - 1 then "└─" else "├─") exit.label;
            go child)
          rest
  in
  go root;
  Buffer.contents buffer
