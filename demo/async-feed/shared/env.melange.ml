type format
type date
type options
type part = { kind : string; [@mel.as "type"] value : string }
type resolved = { timeZone : string }
type media = { matches : bool }

external options :
  ?timeZone:string ->
  ?year:string ->
  ?month:string ->
  ?day:string ->
  ?hour:string ->
  ?minute:string ->
  ?second:string ->
  ?hourCycle:string ->
  ?timeZoneName:string ->
  ?dateStyle:string ->
  ?timeStyle:string ->
  unit ->
  options = "" [@@mel.obj]

external make : string -> options -> format = "DateTimeFormat" [@@mel.new] [@@mel.scope "Intl"]
external resolved : format -> resolved = "resolvedOptions" [@@mel.send]
external date : float -> date = "Date" [@@mel.new]
external format : format -> date -> string = "format" [@@mel.send]
external parts : format -> date -> part array = "formatToParts" [@@mel.send]
external utc : int -> int -> int -> int -> int -> int -> float = "UTC" [@@mel.scope "Date"]
external match_media : string -> media = "matchMedia" [@@mel.scope "window"]

let default_zone () = (resolved (make "en-US" (options ()))).timeZone
let valid_zone zone = match make "en-US" (options ~timeZone:zone ()) with _ -> true | exception _ -> false
let prefers_dark () = (match_media "(prefers-color-scheme: dark)").matches

type formats = { zone : string; short : format; long : format; numeric : format }

let last = ref None

let formats zone =
  match !last with
  | Some formats when formats.zone = zone -> formats
  | _ ->
      let formats =
        {
          zone;
          short =
            make "en-US"
              (options ~timeZone:zone ~year:"numeric" ~month:"short" ~day:"numeric" ~hour:"2-digit" ~minute:"2-digit"
                 ~second:"2-digit" ~hourCycle:"h23" ~timeZoneName:"short" ());
          long = make "en-US" (options ~timeZone:zone ~dateStyle:"full" ~timeStyle:"long" ());
          numeric =
            make "en-US"
              (options ~timeZone:zone ~year:"numeric" ~month:"numeric" ~day:"numeric" ~hour:"numeric" ~minute:"numeric"
                 ~second:"numeric" ~hourCycle:"h23" ());
        }
      in
      last := Some formats;
      formats

let instant time = date (float_of_int time *. 1000.)
let short ~zone time = format (formats zone).short (instant time)
let long ~zone time = format (formats zone).long (instant time) ^ " (" ^ zone ^ ")"

let wall zone ms =
  let fields = parts (formats zone).numeric (date ms) in
  let get kind =
    Array.fold_left
      (fun found part -> if part.kind = kind then Option.value (int_of_string_opt part.value) ~default:0 else found)
      0 fields
  in
  utc (get "year") (get "month" - 1) (get "day") (get "hour") (get "minute") (get "second")

let to_time ~zone value =
  let field start length = if String.length value >= start + length then int_of_string_opt (String.sub value start length) else None in
  match (field 0 4, field 5 2, field 8 2, field 11 2, field 14 2) with
  | Some year, Some month, Some day, Some hour, Some minute ->
      let guess = utc year (month - 1) day hour minute 0 in
      let time = guess -. (wall zone guess -. guess) in
      let time = time -. (wall zone time -. guess) in
      Some (int_of_float (Float.floor (time /. 1000.)))
  | _ -> None

let sync_embed_theme : string -> unit =
  [%mel.raw
    {|function (theme) {
      document.querySelectorAll("iframe.embed-frame").forEach(function (frame) {
        try {
          const doc = frame.contentDocument;
          const root = doc && doc.querySelector(".embed-doc");
          if (root) root.setAttribute("data-theme", theme);
        } catch (_) {}
      });
    }|}]
