let default_zone () = "UTC"
let valid_zone zone = zone = "UTC"
let short ~zone:_ time = Clock.utc time
let day ~zone:_ time = Clock.utc_day time
let clock ~zone:_ time = Clock.utc_clock time
let long ~zone:_ time = Clock.iso time
let to_time ~zone:_ _ = None
let prefers_dark () = false
let sync_embed_theme _ = ()
