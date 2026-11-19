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
  $ printf 'let _ = Yuka__Web.in_browser\n' > native/main.ml
  $ dune build --root . ./native/main.exe 2>&1 | grep -o 'Unbound module Yuka__Web'
  Unbound module Yuka__Web
  $ printf 'let _ = ignore (Yuka.text "x")\n' > native/main.ml
  $ dune build --root . ./native/main.exe

Modules that yuka.mli exposes as an alias, or whose types a consumer must
expand, stay public:

  $ cat > native/main.ml <<'EOF'
  > let _ : Yuka.Json.t = Yuka.Codec.encode Yuka.Codec.int 1
  > let badge = Yuka.element "b" [] []
  > let _ : Yuka.server Yuka.element * Yuka.client Yuka.element = (badge, badge)
  > let _ = Yuka.Status.data
  > let _ = Yuka.Remote.use
  > let _ = Yuka.Live.use
  > let _ = Yuka.Form.make
  > let _ = Yuka.Router.Param.int
  > EOF
  $ dune build --root . ./native/main.exe
