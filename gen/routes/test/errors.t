Generation errors point into Routes.ml

  $ gen () { cat > Routes.ml; yuka-routes --shared --source Routes.ml < Routes.ml; }
Two pages with the same path shape

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a/:x<int>" ~page:P.a;
  >     Router.route B ~path:"/a/:y<string>" ~page:P.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-50:
  Error: path "/a/:y<string>" has the same shape as "/a/:x<int>" (line 3); both answer `GET
  [1]

An endpoint and a page on one path, both GET

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/feed" ~page:P.a;
  >     Router.endpoint B ~path:"/feed" ~method_:`GET ~handler:H.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-62:
  Error: path "/feed" has the same shape as "/feed" (line 3); both answer `GET
  [1]

A redirect answers every method, so it overlaps an action on its path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.action A ~path:"/old" ~method_:`POST ~handler:H.a;
  >     Router.redirect ~path:"/old" ~to_:(Permanent "/new");
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-56:
  Error: path "/old" has the same shape as "/old" (line 3); both answer every method (a redirect)
  [1]

A group path and a route path give the same shape as another route

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/a" [ Router.route A ~path:"/:x<string>" ~page:P.a ];
  >     Router.route B ~path:"/a/:y<int>" ~page:P.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-47:
  Error: path "/a/:y<int>" has the same shape as "/a/:x<string>" (line 3); both answer `GET
  [1]

A name used twice

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:P.a;
  >     Router.route A ~path:"/b" ~page:P.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 17-18:
  Error: name A is used twice (first at line 3)
  [1]

A param label used twice in a branch

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/u/:id<string>"
  >       [ Router.route A ~path:"/p/:id<int>" ~page:P.a ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 29-42:
  Error: label id is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A loader label used twice in a branch

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/u" ~loader:Loaders.user
  >       [ Router.route A ~path:"/" ~page:P.a ~loader:Other.user ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 51-61:
  Error: label user is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A search field with the name of a param

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/u/:id<string>" ~page:P.a
  >       ~search:{ id = optional int };
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 14-35:
  Error: label id is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A group search field and a route search field with one name

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/u" ~search:{ q = optional string }
  >       [ Router.route A ~path:"/" ~page:P.a ~search:{ q = many string } ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 51-70:
  Error: label q is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A redirect target that names an unknown param

  $ gen <<'EOF'
  > Router.make
  >   [ Router.redirect ~path:"/i/:id<string>" ~to_:(Permanent "/issue/:key") ]
  > EOF
  File "Routes.ml", line 2, characters 59-72:
  Error: redirect target "/issue/:key" names :key, which is not a param of the path
  [1]

An action with GET

  $ gen <<'EOF'
  > Router.make [ Router.action A ~path:"/a" ~method_:`GET ~handler:H.a ]
  > EOF
  File "Routes.ml", line 1, characters 50-54:
  Error: Router.action cannot use `GET; use `POST, `PUT, `PATCH or `DELETE
  [1]

An unknown method

  $ gen <<'EOF'
  > Router.make [ Router.endpoint A ~path:"/a" ~method_:`TRACE ~handler:H.a ]
  > EOF
  File "Routes.ml", line 1, characters 52-58:
  Error: ~method_ must be one of `GET, `POST, `PUT, `PATCH, `DELETE
  [1]

A catch-all that is not the last segment

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/docs/:parts<string...>/edit" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-65:
  Error: catch-all :parts in path "/docs/:parts<string...>/edit" must be the last segment
  [1]

A catch-all in a group path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/docs/:parts<string...>"
  >       [ Router.route A ~path:"/" ~page:P.a ];
  >   ]
  > EOF
  File "Routes.ml", line 3, characters 23-48:
  Error: a Router.group path cannot hold a catch-all
  [1]

A trailing slash

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-40:
  Error: path "/a/" has an empty segment or a trailing slash
  [1]

A dot segment

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/../b" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-44:
  Error: path "/a/../b" has a ".." segment
  [1]

An encoded static segment

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/caf%C3%A9" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-47:
  Error: segment "caf%C3%A9" in path "/caf%C3%A9" holds % ? or #; write segments decoded
  [1]

A path without a leading slash

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-38:
  Error: path "a" must start with /
  [1]

An unknown param type

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:x<float>" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-49:
  Error: param :x in path "/a/:x<float>" has type "float"; the types are int, string, string... and a module path
  [1]

A param without a type

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:x" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-42:
  Error: param ":x" in path "/a/:x" must be written :name<type>
  [1]

A param name that is a keyword

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:type<string>" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-53:
  Error: param "type" in path "/a/:type<string>" is not a lowercase OCaml label
  [1]

A label reserved by the generated code

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:P.a
  >       ~search:{ with_query = optional string };
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 14-46:
  Error: label with_query is reserved by the generated code
  [1]

A bad search kind

  $ gen <<'EOF'
  > Router.make
  >   [ Router.route A ~path:"/a" ~page:P.a ~search:{ q = required string } ]
  > EOF
  File "Routes.ml", line 2, characters 54-69:
  Error: search field q must be optional T, default T value or many T
  [1]

A path that is not a literal

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:Paths.a ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-42:
  Error: path must be a string literal
  [1]

A name that is not a constructor

  $ gen <<'EOF'
  > Router.make [ Router.route "a" ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-30:
  Error: the route name must be a constructor such as Issue
  [1]

A route without a name

  $ gen <<'EOF'
  > Router.make [ Router.route ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 14-47:
  Error: Router.route takes the route name (such as Issue) as its one unlabelled argument
  [1]

An unknown node

  $ gen <<'EOF'
  > Router.make [ Router.page A ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 14-48:
  Error: unknown node Router.page; the nodes are Router.make, Router.group, Router.route, Router.endpoint, Router.action and Router.redirect
  [1]

A node that is not a Router call

  $ gen <<'EOF'
  > Router.make [ route A ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 14-42:
  Error: expected a route node such as Router.route Home ~path:"/" ~page:Pages.home
  [1]

An unknown argument

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:P.a ~layout:L.a ]
  > EOF
  File "Routes.ml", line 1, characters 58-61:
  Error: Router.route has no argument ~layout; its labelled arguments are ~path, ~page, ~loader, ~guard, ~search, ~headers, ~cache, ~prerender
  [1]

A missing argument

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ]
  > EOF
  File "Routes.ml", line 1, characters 14-39:
  Error: Router.route needs the argument ~page
  [1]

An argument given twice

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:P.a ~page:P.b ]
  > EOF
  File "Routes.ml", line 1, characters 56-59:
  Error: argument ~page is given twice
  [1]

An optional argument

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:P.a ?guard:None ]
  > EOF
  File "Routes.ml", line 1, characters 57-61:
  Error: ?guard: optional arguments are not supported
  [1]

A route with children

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:P.a
  >       [ Router.route B ~path:"/b" ~page:P.b ];
  >   ]
  > EOF
  File "Routes.ml", lines 3-4, characters 4-45:
  Error: Router.route takes the route name (such as Issue) as its one unlabelled argument
  [1]

A group without a child list

  $ gen <<'EOF'
  > Router.make [ Router.group ~path:"/a" ]
  > EOF
  File "Routes.ml", line 1, characters 14-37:
  Error: Router.group takes a list of child nodes as its one unlabelled argument
  [1]

Children that are not a list literal

  $ gen <<'EOF'
  > Router.make children
  > EOF
  File "Routes.ml", line 1, characters 12-20:
  Error: the child nodes must be a list such as [ Router.route A ~path:"/a" ~page:P.a ]
  [1]

A redirect with a name

  $ gen <<'EOF'
  > Router.make [ Router.redirect A ~path:"/a" ~to_:(Permanent "/b") ]
  > EOF
  File "Routes.ml", line 1, characters 30-31:
  Error: Router.redirect takes no unlabelled argument
  [1]

A redirect target that is not Permanent or Temporary

  $ gen <<'EOF'
  > Router.make [ Router.redirect ~path:"/a" ~to_:"/b" ]
  > EOF
  File "Routes.ml", line 1, characters 46-50:
  Error: ~to_ must be (Permanent "/path") or (Temporary "/path")
  [1]

prerender that is not a literal

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:P.a ~prerender:flag ]
  > EOF
  File "Routes.ml", line 1, characters 61-65:
  Error: ~prerender must be true or false
  [1]

A loader that is not a value path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/a" ~loader:(fun _ -> ())
  >       [ Router.route A ~path:"/" ~page:P.a ];
  >   ]
  > EOF
  File "Routes.ml", line 3, characters 36-49:
  Error: ~loader must be a value path such as Loaders.issue; its last name labels the result
  [1]

A page that is not a value path

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:(P.page ~x:1) ]
  > EOF
  File "Routes.ml", line 1, characters 46-59:
  Error: ~page must be a value path such as Pages.home
  [1]

A handler that is not a value path

  $ gen <<'EOF'
  > Router.make
  >   [ Router.endpoint A ~path:"/a" ~method_:`GET ~handler:(fun _ -> H.a) ]
  > EOF
  File "Routes.ml", line 2, characters 56-70:
  Error: ~handler must be a value path such as Pages.home
  [1]

A nested Router.make

  $ gen <<'EOF'
  > Router.make [ Router.make [] ]
  > EOF
  File "Routes.ml", line 1, characters 14-28:
  Error: Router.make can only be the root
  [1]

A let binding instead of an expression

  $ gen <<'EOF'
  > let routes = Router.make [ Router.route A ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-64:
  Error: the route file must hold one expression, Router.make ..., and nothing else
  [1]

An open before the expression

  $ gen <<'EOF'
  > open Shared
  > ;;
  > Router.make [ Router.route A ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-11:
  Error: the route file must hold one expression, Router.make ..., and nothing else
  [1]

A second expression

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:P.a ];;
  > Router.make [ Router.route B ~path:"/b" ~page:P.b ]
  > EOF
  File "Routes.ml", line 2, characters 0-51:
  Error: the route file must hold one expression, Router.make ..., and nothing else
  [1]

An empty file

  $ gen < /dev/null
  File "Routes.ml", line 1:
  Error: the route file must hold one expression, Router.make ..., and nothing else
  [1]

A syntax error

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:P.a
  > EOF
  File "Routes.ml", line 2, characters 0-0:
  Error: Syntax error: ] expected
  File "Routes.ml", line 1, characters 12-13:
    This [ might be unmatched
  [1]

The root must be Router.make

  $ gen <<'EOF'
  > Router.route A ~path:"/a" ~page:P.a
  > EOF
  File "Routes.ml", line 1, characters 0-35:
  Error: the root must be Router.make
  [1]

Valid input, every node kind, exits 0

  $ gen <<'EOF' > /dev/null
  > Router.make ~layout:L.root ~headers:[ ("x", "y") ] ~cache:No_store ~prerender:false
  >   [
  >     Router.group ~path:"/g/:id<M.Id>" ~layout:L.g ~loader:L.load ~guard:G.ok
  >       ~not_found:P.nf ~error:P.err ~search:{ q = optional string } ~prerender:true
  >       [
  >         Router.route A ~path:"/" ~page:P.a;
  >         Router.endpoint B ~path:"/b" ~method_:`GET ~handler:H.b;
  >         Router.action C ~path:"/b" ~method_:`POST ~handler:H.c;
  >       ];
  >     Router.redirect ~path:"/x" ~to_:(Temporary "/");
  >   ]
  > EOF

A route named Some

  $ gen <<'EOF'
  > Router.make [ Router.route Some ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name Some is a predefined constructor that the generated code uses; choose another name
  [1]

A route named None

  $ gen <<'EOF'
  > Router.make [ Router.route None ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name None is a predefined constructor that the generated code uses; choose another name
  [1]

A route named true

  $ gen <<'EOF'
  > Router.make [ Router.route true ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name true is a predefined constructor that the generated code uses; choose another name
  [1]

A route named false

  $ gen <<'EOF'
  > Router.make [ Router.route false ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-32:
  Error: name false is a predefined constructor that the generated code uses; choose another name
  [1]

A route named ()

  $ gen <<'EOF'
  > Router.make [ Router.route () ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-29:
  Error: name () is a predefined constructor that the generated code uses; choose another name
  [1]

A route named []

  $ gen <<'EOF'
  > Router.make [ Router.route [] ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-29:
  Error: name [] is a predefined constructor that the generated code uses; choose another name
  [1]

A route named ::

  $ gen <<'EOF'
  > Router.make [ Router.route (::) ~path:"/a" ~page:P.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name :: is a predefined constructor that the generated code uses; choose another name
  [1]

No named node

  $ gen <<'EOF'
  > Router.make [ Router.redirect ~path:"/a" ~to_:(Permanent "/b") ]
  > EOF
  File "Routes.ml", line 1:
  Error: the route tree has no named node
  [1]
