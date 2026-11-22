The rules of getting-started.md that run yuka islands and yuka css read
the sources of shared, not its build directory, where dune writes other
files during the same build

  $ mkdir -p project/shared project/client project/server
  $ printf '(lang dune 3.16)\n' > project/dune-project
  $ awk -v RS= '/^\(rule/ && /bin:yuka} css/' ../../docs/getting-started.md | grep -v '^```' > project/server/dune
  $ awk -v RS= '/^\(rule/ && /bin:yuka} islands/' ../../docs/getting-started.md | grep -v '^```' > project/client/dune
  $ cat > project/shared/dune <<'EOF'
  > (library (name app_shared) (modules :standard \ stray))
  > (rule (targets stray.ml) (action (write-file stray.ml "let sheet = [%yuka.css \"missing.css\"]\n")))
  > EOF
  $ printf '.button { color: red }\n' > project/shared/counter.css
  $ printf 'module Css = [%%yuka.css "counter.css"]\nlet[@client] make () = ()\n' > project/shared/counter.mlx
  $ cd project
  $ dune build --root . shared/stray.ml
  $ dune build --root . server/yuka_css.ml client/yuka_islands.ml client/yuka_islands.json
  $ cat _build/default/server/yuka_css.ml
  let sheets = [
    ("counter-8620c5e2.css", ".button_8620c5e2 { color: red }\n");
  ]
  $ cat _build/default/client/yuka_islands.json
  {
    "App_shared.Counter": "../shared/counter.js"
  }

The rule of getting-started.md that runs yuka assets writes the module and
the directory of hashed files:

  $ cd ..
  $ mkdir -p media/shared media/images
  $ printf '(lang dune 3.16)\n(using directory-targets 0.1)\n' > media/dune-project
  $ awk -v RS= '/\(rule/ && /bin:yuka} assets/' ../../docs/getting-started.md | grep -v '^```' > media/shared/dune
  $ printf 'GIF89a\012\000\005\000' > media/images/dot.gif
  $ (cd media && dune build --root . shared/images.ml shared/img)
  $ cat media/_build/default/shared/images.ml
  let dot : Yuka.Image.t =
    { Yuka.Image.src = "/_yuka/img/dot-cc3a4e41.gif"; width = 10; height = 5;
      srcset = [ ("/_yuka/img/dot-cc3a4e41.gif", 10) ] }
  $ ls media/_build/default/shared/img
  dot-cc3a4e41.gif
