A Melange build of a Yuka client lists only yuka:

  $ unset DUNE_BUILD_DIR
  $ export OCAMLPATH="$(dirname "$(command -v yuka)")/../lib"
  $ printf '(lang dune 3.16)\n(using melange 0.1)\n' > dune-project
  $ printf 'let () = ignore (Yuka.text "x")\n' > main.ml
  $ printf '(melange.emit\n (target out)\n (libraries yuka))\n' > dune
  $ dune build --root . 2>&1
  $ ls _build/default/out/main.js
  _build/default/out/main.js

Most internal modules are private:

  $ mkdir native && printf '(executable\n (name main)\n (libraries yuka))\n' > native/dune
  $ printf 'let _ = Yuka__Server.handle\n' > native/main.ml
  $ dune build --root . ./native/main.exe 2>&1 | grep -o 'Unbound module Yuka__Server'
  Unbound module Yuka__Server
  $ printf 'let _ = Yuka__Signal.create\n' > native/main.ml
  $ dune build --root . ./native/main.exe 2>&1 | grep -o 'Unbound module Yuka__Signal'
  Unbound module Yuka__Signal
  $ printf 'let _ = ignore (Yuka.text "x")\n' > native/main.ml
  $ dune build --root . ./native/main.exe
