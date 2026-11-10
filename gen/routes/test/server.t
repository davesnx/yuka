Server output errors point into Routes.mlx

  $ gen () { cat > Routes.mlx; mlx-pp Routes.mlx > routes.ast && yuka-routes --server --shared-module Shared.Routes routes.ast > out.ml; }

not_found under a layout that takes a loader result

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/issue/:id<string>" loader=L.issue layout=Layouts.issue
  >       not_found=P.missing>
  >       <Route name=Issue path="/" page=P.issue />
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 16-25:
  Error: not_found here renders inside the layout at line 3, which takes a loader result; declare not_found on a node above the loader
  [1]

error under a layout below a loader

  $ gen <<'EOF'
  > let routes =
  >   <Router layout=Layouts.root>
  >     <Group path="/issue/:id<string>" loader=L.issue>
  >       <Group path="/edit" layout=Layouts.edit error=P.error>
  >         <Route name=Edit path="/" page=P.edit />
  >       </Group>
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 52-59:
  Error: error here renders inside the layout at line 4, which takes a loader result; declare error on a node above the loader
  [1]

not_found below a loader but outside data layouts is fine

  $ gen <<'EOF'
  > let routes =
  >   <Router layout=Layouts.root>
  >     <Group path="/issue/:id<string>" loader=L.issue not_found=P.missing>
  >       <Route name=Issue path="/" page=P.issue />
  >     </Group>
  >   </Router>
  > EOF
  $ grep -A 8 '^let fallback_1' out.ml
  let fallback_1 : Yuka.Server.fallback =
    {
      Yuka.Server.layers =
        [
          layer_0;
        ];
      not_found = (fun target -> P.missing ~target ());
      error = Yuka.Server.default_error;
    }

A fallback inside a param group with a layout is built in the arm, where
the param is bound

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/t/:team<string>" layout=L.team>
  >       <Group path="/x" not_found=NF.page>
  >         <Route name=X path="/" page=P.x />
  >       </Group>
  >     </Group>
  >   </Router>
  > EOF
  $ grep -c '^let fallback' out.ml
  1
  $ grep 'let layer_0' out.ml
        let layer_0 = { Yuka.Server.key = Stdlib.String.concat "/" [ "L0"; Yuka.Router.encode team ]; wrap = (fun children -> L.team ~children ()) } in
  $ grep -A 8 'fallback = {' out.ml
            fallback = {
              Yuka.Server.layers =
                [
                  layer_0;
                ];
              not_found = (fun target -> NF.page ~target ());
              error = Yuka.Server.default_error;
            };
            load =

The generated code names its request req

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/" page=P.a loader=L.req />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 43-48:
  Error: label req is reserved by the generated code
  [1]

The shared module must be a module path

  $ yuka-routes --server --shared-module shared routes.ast
  usage: yuka-routes --shared FILE.ast
         yuka-routes --server --shared-module MODULE FILE.ast
  [2]
