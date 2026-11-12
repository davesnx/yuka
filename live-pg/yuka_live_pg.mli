val bus : ?retry:float -> conninfo:string -> channel:string -> unit -> Yuka.Server.Live.bus
(** A bus over Postgres [LISTEN]/[NOTIFY] on [channel], for
    {!Yuka.Server.Live.use_bus}. It opens two connections with [conninfo]
    (libpq syntax, for example ["host=db dbname=app user=app"]): one sends
    each note with [pg_notify], one listens. The listening connection waits
    on its socket with Lwt, so it does not block other requests; sending is
    a short query on the other connection. When a connection fails, it
    connects again every [retry] seconds (default 1); after the listening
    connection comes back, it calls the [on_restart] functions, because
    notes sent meanwhile are lost. Run it under [Lwt_main.run] (as Dream
    does). Postgres limits a note to 8,000 bytes, which
    [Yuka.Server.Live.publish] checks. [Yuka.Server.Live.close_bus] stops
    listening and closes both connections; later sends fail. *)
