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
  "Yuka renders pages on the server and streams slow parts as they become ready. It does not depend on a web server: you connect it to Dream, or any other, in a few lines. Parts that need interaction are islands: small components that Melange compiles to JavaScript and that hydrate in the browser. Components are written in mlx (JSX for OCaml) and use signals, so a component runs once and only the parts that read a signal update.")
 (depends
  (ocaml
   (>= 5.4))
  (melange
   (>= 7.0.1-54))
  (ppxlib
   (>= 0.38.0))
  (mlx :with-test)
  (alcotest :with-test)
  (dream :with-test)
  (lwt :with-test)
  (odoc :with-doc)))
