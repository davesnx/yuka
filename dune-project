(lang dune 3.16)

(using melange 0.1)

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
   (>= 0.38.0))
  (mlx :with-test)
  (alcotest :with-test)
  (odoc :with-doc)))

(package
 (name yuka-dream)
 (synopsis "Run a Yuka app on the Dream web server")
 (description
  "The request cycle of Yuka on Dream: one handler that serves the routes of Routes.mlx, the client JavaScript and public files, and a prerender that writes the pages marked prerender=true to a directory.")
 (depends
  (ocaml
   (>= 5.4))
  (yuka
   (= :version))
  (dream
   (>= 1.0.0~alpha8))
  lwt
  (mlx :with-test)
  (alcotest :with-test)
  (odoc :with-doc)))
