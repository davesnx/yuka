(lang dune 3.25)

(using melange 1.0)

(generate_opam_files true)

(source
 (github davesnx/yuka))

(authors "David Sancho Moreno")

(maintainers "David Sancho Moreno")

(license MIT)

(dialect
 (name mlx)
 (implementation
  (extension mlx)
  (merlin_reader mlx)
  (preprocess
   (run mlx-pp %{input-file}))))

(package
 (name yuka)
 (synopsis "Web framework for OCaml, server-rendered, with islands")
 (description
  "Yuka renders pages on the server and streams slow parts as they become ready. It does not depend on a web server: the yuka-dream package runs an app on Dream, and another server needs one small adapter. Parts that need interaction are islands: small components that Melange compiles to JavaScript and that hydrate in the browser. Components are written in mlx (JSX for OCaml) and use signals, so a component runs once and only the parts that read a signal update.")
 (depends
  (ocaml
   (>= 5.4))
  (melange
   (>= 7.0.1-54))
  (ppxlib
   (and
    (>= 0.38.0)
    (< 0.40.0)))
  (mlx
   (and
    (>= 0.12)
    (< 0.13)))
  (alcotest :with-test)
  (odoc :with-doc)))

(package
 (name yuka-dream)
 (synopsis "Run a Yuka app on the Dream web server")
 (description
  "The request cycle of Yuka on Dream: one handler that serves the routes of Routes.ml, the client JavaScript and public files, and a prerender that writes the pages marked ~prerender:true to a directory.")
 (depends
  (ocaml
   (>= 5.4))
  (yuka
   (= :version))
  (dream
   (>= 1.0.0~alpha8))
  lwt
  (mlx
   (and
    :with-test
    (>= 0.12)))
  (alcotest :with-test)
  (odoc :with-doc)))

(package
 (name yuka-tapak)
 (synopsis "Run a Yuka app on the tapak web server (Eio)")
 (description
  "The request cycle of Yuka on tapak: one handler that serves the routes of Routes.ml, the client JavaScript, public files and the live socket, in direct style on Eio.")
 (depends
  (ocaml
   (>= 5.4))
  (yuka
   (= :version))
  tapak
  cows
  eio
  bytesrw
  http
  logs
  (eio_main :with-test)
  (alcotest :with-test)
  (odoc :with-doc)))

(package
 (name yuka-live-pg)
 (synopsis "A Postgres LISTEN/NOTIFY bus for the live data of Yuka")
 (description
  "Server.Live.use_bus with Postgres: each server node of a Yuka app tells the other nodes that a live key changed through NOTIFY on one channel, and listens with LISTEN on its own connection.")
 (depends
  (ocaml
   (>= 5.4))
  (yuka
   (= :version))
  (postgresql
   (>= 5.0))
  lwt
  (alcotest :with-test)
  (odoc :with-doc)))
