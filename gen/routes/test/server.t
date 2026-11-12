Server output errors point into Routes.ml

  $ gen () { cat > Routes.ml; yuka routes --server --shared-module Shared.Routes --source Routes.ml > out.ml; }

not_found under a layout that takes a loader result

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue ~layout:Layouts.issue
  >       ~not_found:Pages.missing
  >       [ Router.route Issue ~path:"/" ~page:Pages.issue ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 17-30:
  Error: not_found here renders inside the layout at line 3, which takes a loader result; declare not_found on a node above the loader
  [1]

error under a layout below a loader

  $ gen <<'EOF'
  > Router.make ~layout:Layouts.root
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue
  >       [
  >         Router.group ~path:"/edit" ~layout:Layouts.edit ~error:Pages.error
  >           [ Router.route Edit ~path:"/" ~page:Pages.edit ];
  >       ];
  >   ]
  > EOF
  File "Routes.ml", line 5, characters 63-74:
  Error: error here renders inside the layout at line 5, which takes a loader result; declare error on a node above the loader
  [1]

not_found below a loader but outside data layouts is fine

  $ gen <<'EOF'
  > Router.make ~layout:Layouts.root
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue ~not_found:Pages.missing
  >       [ Router.route Issue ~path:"/" ~page:Pages.issue ];
  >   ]
  > EOF
  $ grep 'not_found =' out.ml
      not_found = Yuka.Server.Generated.default_not_found;
              not_found = (fun path -> Pages.missing ~id ~path ());

not_found gets the params of the path of its node and ~path, so no param
there can be named path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/t/:path<string>" ~not_found:Pages.missing
  >       [ Router.route T ~path:"/" ~page:Pages.t ];
  >   ]
  > EOF
  File "Routes.ml", line 3, characters 53-66:
  Error: not_found takes ~path, so no param of its path can be named path
  [1]

A fallback inside a param group with a layout is built in the arm, where
the param is bound

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/t/:team<string>" ~layout:Layouts.team
  >       [
  >         Router.group ~path:"/x" ~not_found:NF.page
  >           [ Router.route X ~path:"/" ~page:Pages.x ];
  >       ];
  >   ]
  > EOF
  $ grep -c '^let fallback' out.ml
  1
  $ grep 'let layer_0' out.ml
        let layer_0 = { Yuka.Server.Generated.key = Stdlib.String.concat "/" [ "L0"; Yuka.Router.encode team ]; data = false; wrap = (fun children -> Layouts.team ~children ()) } in
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
  >     Router.endpoint Hook ~path:"/hook" ~method_:`POST ~handler:Handlers.hook ~cross_origin:true;
  >     Router.endpoint Put ~path:"/put" ~method_:`PUT ~handler:Handlers.put;
  >     Router.action Act ~path:"/act" ~method_:`POST ~handler:Handlers.act;
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
  > Router.make [ Router.endpoint Hook ~path:"/hook" ~method_:`POST ~handler:Handlers.hook ~cross_origin:yes ]
  > EOF
  File "Routes.ml", line 1, characters 101-104:
  Error: ~cross_origin must be true or false
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.action Act ~path:"/act" ~method_:`POST ~handler:Handlers.act ~cross_origin:true ]
  > EOF
  File "Routes.ml", line 1, characters 96-100:
  Error: Router.action has no argument ~cross_origin; its labelled arguments are ~path, ~method_, ~handler, ~guard, ~headers, ~cache, ~prerender
  [1]

A cache value is read with Yuka.Server opened

  $ gen <<'EOF'
  > Router.make ~cache:(public ~max_age:60 ()) [ Router.route A ~path:"/" ~page:Pages.a ]
  > EOF
  $ grep 'cache' out.ml
    Yuka.Server.Generated.rules ~headers:[  ] ~cache:(Yuka.Server.(public ~max_age:60 ()) [@warning "-33"]) ~prerender:false ()

Items before the tree go, as written, at the top of the server module; a
let in ~cache keeps its own value, and a punned label is a short path

  $ gen <<'EOF'
  > (* the pages *)
  > open Pages
  > 
  > let week = Yuka.Server.public ~max_age:604800 ()
  > let security = [ ("x-frame-options", "DENY") ]
  > 
  > let routes =
  >   Router.make ~not_found ~headers:security
  >     [ Router.route About ~path:"/about" ~page:about ~cache:week ]
  > EOF
  $ head -7 out.ml
  (* the pages *)
  open Pages
  
  let week = Yuka.Server.public ~max_age:604800 ()
  let security = [ ("x-frame-options", "DENY") ]
  
  let rules_0 =
  $ grep -e 'cache' -e 'not_found =' -e 'page =' -e '~headers:(' out.ml
    Yuka.Server.Generated.rules ~headers:[ security ] ~cache:(Yuka.Server.(week) [@warning "-33"]) ~prerender:false ()
      not_found = (fun path -> not_found ~path ());
                       page = about ();
      ~headers:(security)

The shared module leaves the items out

  $ yuka routes --shared --source Routes.ml | grep -c -e Pages -e week
  0
  [1]

The build id changes with the items before the tree

  $ grep -o 'build:"[0-9a-f]*"' out.ml > before
  $ sed 's/604800/86400/' Routes.ml > Routes.next && mv Routes.next Routes.ml
  $ yuka routes --server --shared-module Shared.Routes --source Routes.ml | grep -o 'build:"[0-9a-f]*"' > after
  $ cmp -s before after
  [1]

The binding of the tree is not copied, so an item named routes is the
user's value

  $ gen <<'EOF'
  > let routes = Pages.about
  > let routes = Router.make [ Router.route About ~path:"/about" ~page:routes ]
  > EOF
  $ head -2 out.ml
  let routes = Pages.about
  
  $ grep 'page =' out.ml
                       page = routes ();

A short attachment that the generated code would hide

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue
  >       [ Router.route Issue ~path:"/" ~page:issue ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 43-48:
  Error: ~page:issue is hidden by the param, search field or loader result issue of the route Issue; write it with its module path
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route Issue ~path:"/issue/:id<string>" ~page:id ]
  > EOF
  File "Routes.ml", line 1, characters 66-68:
  Error: ~page:id is hidden by the param, search field or loader result id of the route Issue; write it with its module path
  [1]

  $ gen <<'EOF'
  > Router.make ~layout:children [ Router.route A ~path:"/" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 20-28:
  Error: ~layout:children is hidden by a name of the generated server code (req, children, path, rules_N, layer_N, fallback_N); write it with its module path
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/" ~page:Pages.a ~guard:rules_0 ]
  > EOF
  File "Routes.ml", line 1, characters 60-67:
  Error: ~guard:rules_0 is hidden by a name of the generated server code (req, children, path, rules_N, layer_N, fallback_N); write it with its module path
  [1]

The generated code names its request req

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/" ~page:Pages.a ~loader:Loaders.req ]
  > EOF
  File "Routes.ml", line 1, characters 61-72:
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
