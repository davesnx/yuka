(* The records in the crate, made up. *)

let hex hue saturation lightness =
  let hue = Float.rem hue 360. in
  let chroma = (1. -. Float.abs ((2. *. lightness) -. 1.)) *. saturation in
  let x = chroma *. (1. -. Float.abs (Float.rem (hue /. 60.) 2. -. 1.)) in
  let r, g, b =
    if hue < 60. then (chroma, x, 0.)
    else if hue < 120. then (x, chroma, 0.)
    else if hue < 180. then (0., chroma, x)
    else if hue < 240. then (0., x, chroma)
    else if hue < 300. then (x, 0., chroma)
    else (chroma, 0., x)
  in
  let m = lightness -. (chroma /. 2.) in
  let byte value = Int.max 0 (Int.min 255 (Float.to_int (Float.round ((value +. m) *. 255.)))) in
  Printf.sprintf "#%02X%02X%02X" (byte r) (byte g) (byte b)

type album = { id : int; title : string; artist : string; year : int; genre : string; tracks : string list }

let genres = [ "Jazz"; "Electronic"; "Folk"; "Soul" ]

let albums =
  List.mapi
    (fun i (title, artist, year, genre, tracks) -> { id = i + 1; title; artist; year; genre; tracks })
    [
      ("Blue Hours", "The Marlowe Trio", 1962, "Jazz", [ "Opening Night"; "Blue Hours"; "Rain on Seventh"; "Lantern"; "Last Call" ]);
      ("Night Signal", "Kaito Mori", 2019, "Electronic", [ "Carrier"; "Night Signal"; "Static Bloom"; "Low Orbit"; "Relay"; "Dawn Packet" ]);
      ("Wild Orchard", "June & the Pines", 2011, "Folk", [ "Apple Wind"; "Wild Orchard"; "Creek Song"; "Old Fence" ]);
      ("Velvet Room", "Odessa Gray", 1971, "Soul", [ "Velvet Room"; "Hold Me Slow"; "Sunday Shoes"; "Gold Tooth Grin"; "Amen Again" ]);
      ("Tidal", "Nora Vale Quartet", 1958, "Jazz", [ "Undertow"; "Tidal"; "Salt"; "Harbor Lights"; "Drift" ]);
      ("Polar Arcade", "Glass Animals Club", 2022, "Electronic", [ "Insert Coin"; "Polar Arcade"; "High Score"; "Ice Level"; "Continue?" ]);
      ("Paper Boats", "Elsie Fold", 2015, "Folk", [ "Paper Boats"; "Kite Strings"; "Hometown"; "The Long Field"; "Lullaby" ]);
      ("Golden Hour", "The Sweethearts", 1968, "Soul", [ "Golden Hour"; "Honey Do"; "Back Porch"; "Ain't It Grand" ]);
      ("Smoke Rings", "Leon Ashby", 1965, "Jazz", [ "Smoke Rings"; "Basement Session"; "Valve"; "Brushes"; "Coda" ]);
      ("Neon Tundra", "Sola", 2020, "Electronic", [ "Aurora Loop"; "Neon Tundra"; "Snowfield"; "Permafrost"; "Thaw" ]);
      ("Canyon Letters", "Ruth & Abel", 2008, "Folk", [ "Dear River"; "Canyon Letters"; "Dust Road"; "Coyote Moon" ]);
      ("Coral", "Marvin Bell & the Tides", 1974, "Soul", [ "Coral"; "Ocean Love"; "Shellfish Shuffle"; "Undertow Blues"; "Shore" ]);
      ("Lunar Suite", "Ida Okafor", 1977, "Jazz", [ "First Quarter"; "Gibbous"; "Full"; "Waning"; "New Moon" ]);
      ("Ember", "Pale Circuit", 2017, "Electronic", [ "Spark"; "Ember"; "Kindling"; "Ashfall"; "Smoulder"; "Heat Death" ]);
      ("Meadow", "The Hollow Reeds", 2013, "Folk", [ "Clover"; "Meadow"; "Hay Bale"; "Swallows" ]);
      ("Candied", "Lula Shaw", 1966, "Soul", [ "Candied"; "Sugar Rush"; "Sweet Thing"; "Rock Candy"; "Toffee" ]);
    ]

(* The loader of the album page: the not-found page, status 404, for a number that is not in the crate. *)
let album (_ : Yuka.Server.request) ~id =
  Yuka.Async.return
    (match List.find_opt (fun album -> album.id = id) albums with Some album -> Ok album | None -> Error Yuka.Server.Not_found)

let around id =
  let count = List.length albums in
  let at n = List.nth albums ((((n - 1) mod count) + count) mod count) in
  (at (id - 1), at (id + 1))
