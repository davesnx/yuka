Server output errors point into Routes.ml

  $ gen () { cat > Routes.ml; yuka routes --server --shared-module Shared.Routes --source Routes.ml > out.ml; }

not_found under a layout that takes a loader result

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:L.issue ~layout:Layouts.issue
  >       ~not_found:P.missing
  >       [ Router.route Issue ~path:"/" ~page:P.issue ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 17-26:
  Error: not_found here renders inside the layout at line 3, which takes a loader result; declare not_found on a node above the loader
  [1]

error under a layout below a loader

  $ gen <<'EOF'
  > Router.make ~layout:Layouts.root
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:L.issue
  >       [
  >         Router.group ~path:"/edit" ~layout:Layouts.edit ~error:P.error
  >           [ Router.route Edit ~path:"/" ~page:P.edit ];
  >       ];
  >   ]
  > EOF
  File "Routes.ml", line 5, characters 63-70:
  Error: error here renders inside the layout at line 5, which takes a loader result; declare error on a node above the loader
  [1]

not_found below a loader but outside data layouts is fine

  $ gen <<'EOF'
  > Router.make ~layout:Layouts.root
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:L.issue ~not_found:P.missing
  >       [ Router.route Issue ~path:"/" ~page:P.issue ];
  >   ]
  > EOF
  $ grep 'not_found =' out.ml
      not_found = Yuka.Server.Generated.default_not_found;
              not_found = (fun path -> P.missing ~id ~path ());

not_found gets the params of the path of its node and ~path, so no param
there can be named path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/t/:path<string>" ~not_found:P.missing
  >       [ Router.route T ~path:"/" ~page:P.t ];
  >   ]
  > EOF
  File "Routes.ml", line 3, characters 53-62:
  Error: not_found takes ~path, so no param of its path can be named path
  [1]

A fallback inside a param group with a layout is built in the arm, where
the param is bound

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/t/:team<string>" ~layout:L.team
  >       [
  >         Router.group ~path:"/x" ~not_found:NF.page
  >           [ Router.route X ~path:"/" ~page:P.x ];
  >       ];
  >   ]
  > EOF
  $ grep -c '^let fallback' out.ml
  1
  $ grep 'let layer_0' out.ml
        let layer_0 = { Yuka.Server.Generated.key = Stdlib.String.concat "/" [ "L0"; Yuka.Router.encode team ]; data = false; wrap = (fun children -> L.team ~children ()) } in
  $ grep -A 8 'fallback = {' out.ml
            fallback = {
              Yuka.Server.Generated.layers =
                [
                  layer_0;
                ];
              not_found = (fun path -> NF.page ~team ~path ());
              error = Yuka.Server.Generated.default_error;
            };
            load =

An endpoint with ~cross_origin:true skips the origin check; an action
never does

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.endpoint Hook ~path:"/hook" ~method_:`POST ~handler:H.hook ~cross_origin:true;
  >     Router.endpoint Put ~path:"/put" ~method_:`PUT ~handler:H.put;
  >     Router.action Act ~path:"/act" ~method_:`POST ~handler:H.act;
  >   ]
  > EOF
  $ grep -E 'action =|cross_origin =' out.ml
            action = false;
            cross_origin = true;
            action = false;
            cross_origin = false;
            action = true;
            cross_origin = false;

  $ gen <<'EOF'
  > Router.make [ Router.endpoint Hook ~path:"/hook" ~method_:`POST ~handler:H.hook ~cross_origin:yes ]
  > EOF
  File "Routes.ml", line 1, characters 94-97:
  Error: ~cross_origin must be true or false
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.action Act ~path:"/act" ~method_:`POST ~handler:H.act ~cross_origin:true ]
  > EOF
  File "Routes.ml", line 1, characters 89-93:
  Error: Router.action has no argument ~cross_origin; its labelled arguments are ~path, ~method_, ~handler, ~guard, ~headers, ~cache, ~prerender
  [1]

A cache value is read with Yuka.Server opened

  $ gen <<'EOF'
  > Router.make ~cache:(public ~max_age:60 ()) [ Router.route A ~path:"/" ~page:P.a ]
  > EOF
  $ grep 'cache' out.ml
    Yuka.Server.Generated.rules ~headers:[  ] ~cache:Yuka.Server.(public ~max_age:60 ()) ~prerender:false ()

The generated code names its request req

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/" ~page:P.a ~loader:L.req ]
  > EOF
  File "Routes.ml", line 1, characters 57-62:
  Error: label req is reserved by the generated code
  [1]

The shared module must be a module path

  $ yuka routes --server --shared-module shared --source Routes.ml
  yuka routes: --shared-module takes a module path such as App.Routes, not "shared".
  usage: yuka routes --source FILE --shared
         yuka routes --source FILE --server --shared-module MODULE
  Read the route tree in FILE (Routes.ml) and print the shared module (--shared) or the server module (--server).
    --source FILE          The route file, Routes.ml
    --shared               Print the shared module: the route type, href and find
    --server               Print the server module: the app of the routes
    --shared-module MODULE The module path of the shared module, for --server
    -help                  Display this list of options
    --help                 Display this list of options
  [2]
