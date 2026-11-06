val handler :
  ?not_found:Dream.handler ->
  Dream.handler Yuka_router.case list ->
  Dream.handler
(** [handler cases] matches [Dream.target] against the cases in order and
    runs the handler of the first match. A path that matches no case goes to
    [not_found] (default: an empty 404 response). Mount it for every path:
    [Dream.get "/**" (handler cases)].

    Each page handler must call [Yuka_server.respond ~request], so that a
    request with [Yuka-Navigate: 1] gets the settled page. *)
