Generation errors point into Routes.ml

  $ gen () { cat > Routes.ml; yuka routes --shared --source Routes.ml; }
Two pages with the same path shape

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a/:x<int>" ~page:Pages.a;
  >     Router.route B ~path:"/a/:y<string>" ~page:Pages.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-54:
  Error: path "/a/:y<string>" has the same shape as "/a/:x<int>" (line 3); both answer `GET
  [1]

An endpoint and a page on one path, both GET

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/feed" ~page:Pages.a;
  >     Router.endpoint B ~path:"/feed" ~method_:`GET ~handler:Handlers.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-69:
  Error: path "/feed" has the same shape as "/feed" (line 3); both answer `GET
  [1]

A redirect answers every method, so it overlaps an action on its path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.action A ~path:"/old" ~method_:`POST ~handler:Handlers.a;
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
  >     Router.group ~path:"/a" [ Router.route A ~path:"/:x<string>" ~page:Pages.a ];
  >     Router.route B ~path:"/a/:y<int>" ~page:Pages.b;
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 4-51:
  Error: path "/a/:y<int>" has the same shape as "/a/:x<string>" (line 3); both answer `GET
  [1]

A name used twice

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:Pages.a;
  >     Router.route A ~path:"/b" ~page:Pages.b;
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
  >       [ Router.route A ~path:"/p/:id<int>" ~page:Pages.a ];
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
  >       [ Router.route A ~path:"/" ~page:Pages.a ~loader:Other.user ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 55-65:
  Error: label user is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A search field with the name of a param

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/u/:id<string>" ~page:Pages.a
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
  >       [ Router.route A ~path:"/" ~page:Pages.a ~search:{ q = many string } ];
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 55-74:
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
  > Router.make [ Router.action A ~path:"/a" ~method_:`GET ~handler:Handlers.a ]
  > EOF
  File "Routes.ml", line 1, characters 50-54:
  Error: Router.action cannot use `GET; use `POST, `PUT, `PATCH or `DELETE
  [1]

An unknown method

  $ gen <<'EOF'
  > Router.make [ Router.endpoint A ~path:"/a" ~method_:`TRACE ~handler:Handlers.a ]
  > EOF
  File "Routes.ml", line 1, characters 52-58:
  Error: ~method_ must be one of `GET, `POST, `PUT, `PATCH, `DELETE
  [1]

A catch-all that is not the last segment

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/docs/:parts<string...>/edit" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-65:
  Error: catch-all :parts in path "/docs/:parts<string...>/edit" must be the last segment
  [1]

A catch-all in a group path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/docs/:parts<string...>"
  >       [ Router.route A ~path:"/" ~page:Pages.a ];
  >   ]
  > EOF
  File "Routes.ml", line 3, characters 23-48:
  Error: a Router.group path cannot hold a catch-all
  [1]

A trailing slash

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-40:
  Error: path "/a/" has an empty segment or a trailing slash
  [1]

A dot segment

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/../b" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-44:
  Error: path "/a/../b" has a ".." segment
  [1]

An encoded static segment

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/caf%C3%A9" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-47:
  Error: segment "caf%C3%A9" in path "/caf%C3%A9" holds % ? or #; write segments decoded
  [1]

A path without a leading slash

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-38:
  Error: path "a" must start with /
  [1]

An unknown param type

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:x<float>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-49:
  Error: param :x in path "/a/:x<float>" has type "float"; the types are int, string, string... and a type with its module path, such as Model.issue_id
  [1]

A param type that names a module

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:id<Issue_id>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-53:
  Error: param :id in path "/a/:id<Issue_id>" names the module Issue_id; write its type: :id<Issue_id.t>
  [1]

A param type without its module

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:id<issue_id>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-53:
  Error: param :id in path "/a/:id<issue_id>" has type "issue_id"; the types are int, string, string... and a type with its module path, such as Model.issue_id
  [1]

A param type with a parameter

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:x<int list>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-52:
  Error: param :x in path "/a/:x<int list>" has type "int list"; the types are int, string, string... and a type with its module path, such as Model.issue_id
  [1]

A search type that names a module

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~search:{ tab = optional Tab } ]
  > EOF
  File "Routes.ml", line 1, characters 79-82:
  Error: search field tab names the module Tab; write its type: optional Tab.t
  [1]

A search type without its module

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~search:{ sort = default sort Newest } ]
  > EOF
  File "Routes.ml", line 1, characters 79-83:
  Error: search field sort has type "sort"; the types are int, string, bool and a type with its module path, such as Model.issue_id
  [1]

A search type with a parameter

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~search:{ ids = many (int list) } ]
  > EOF
  File "Routes.ml", line 1, characters 75-85:
  Error: search field ids has type "int list"; the types are int, string, bool and a type with its module path, such as Model.issue_id
  [1]

A param without a type

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:x" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-42:
  Error: param ":x" in path "/a/:x" must be written :name<type>
  [1]

A param name that is a keyword

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:type<string>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-53:
  Error: param "type" in path "/a/:type<string>" is not a lowercase OCaml label
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:effect<string>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-55:
  Error: param "effect" in path "/a/:effect<string>" is not a lowercase OCaml label
  [1]

A label reserved by the generated code

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:Pages.a
  >       ~search:{ with_query = optional string };
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 14-46:
  Error: label with_query is reserved by the generated code
  [1]

A param named href, which the route helpers call

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:href<string>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-53:
  Error: label href is reserved by the generated code
  [1]

A search field named fragment, which is the last argument of each route helper

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:Pages.a
  >       ~search:{ fragment = optional string };
  >   ]
  > EOF
  File "Routes.ml", line 4, characters 14-44:
  Error: label fragment is reserved by the generated code
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a/:fragment<string>" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-57:
  Error: label fragment is reserved by the generated code
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~loader:Loaders.fragment ]
  > EOF
  File "Routes.ml", line 1, characters 62-78:
  Error: label fragment is reserved by the generated code
  [1]

A route name whose helper is a keyword

  $ gen <<'EOF'
  > Router.make [ Router.route Type ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name Type makes the helper Routes.type, which is an OCaml keyword; choose another name
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.endpoint Method ~path:"/a" ~method_:`GET ~handler:Handlers.a ]
  > EOF
  File "Routes.ml", line 1, characters 30-36:
  Error: name Method makes the helper Routes.method, which is an OCaml keyword; choose another name
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.action Effect ~path:"/a" ~method_:`POST ~handler:Handlers.a ]
  > EOF
  File "Routes.ml", line 1, characters 28-34:
  Error: name Effect makes the helper Routes.effect, which is an OCaml keyword; choose another name
  [1]

A route name whose helper the generated code already defines

  $ gen <<'EOF'
  > Router.make [ Router.route Href ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name Href makes the helper Routes.href, which the generated code already defines; choose another name
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route Find ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name Find makes the helper Routes.find, which the generated code already defines; choose another name
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route With_query ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-37:
  Error: name With_query makes the helper Routes.with_query, which the generated code already defines; choose another name
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route With_fragment ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-40:
  Error: name With_fragment makes the helper Routes.with_fragment, which the generated code already defines; choose another name
  [1]

A bad search kind

  $ gen <<'EOF'
  > Router.make
  >   [ Router.route A ~path:"/a" ~page:Pages.a ~search:{ q = required string } ]
  > EOF
  File "Routes.ml", line 2, characters 58-73:
  Error: search field q must be optional T, default T value or many T
  [1]

A path that is not a literal

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:Paths.a ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 35-42:
  Error: path must be a string literal
  [1]

A name that is not a constructor

  $ gen <<'EOF'
  > Router.make [ Router.route "a" ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-30:
  Error: the route name must be a constructor such as Issue
  [1]

A route without a name

  $ gen <<'EOF'
  > Router.make [ Router.route ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 14-51:
  Error: Router.route takes the route name (such as Issue) as its one unlabelled argument
  [1]

An unknown node

  $ gen <<'EOF'
  > Router.make [ Router.page A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 14-52:
  Error: unknown node Router.page; the nodes are Router.make, Router.group, Router.route, Router.endpoint, Router.action and Router.redirect (names of the route file syntax, not OCaml values)
  [1]

A node that is not a Router call

  $ gen <<'EOF'
  > Router.make [ route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 14-46:
  Error: expected a route node such as Router.route Home ~path:"/" ~page:Pages.home
  [1]

An unknown argument

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~layout:Layouts.a ]
  > EOF
  File "Routes.ml", line 1, characters 62-71:
  Error: Router.route has no argument ~layout; its labelled arguments are ~path, ~page, ~loader, ~guard, ~search, ~prefetch, ~headers, ~cache, ~prerender
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
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~page:Pages.b ]
  > EOF
  File "Routes.ml", line 1, characters 60-67:
  Error: argument ~page is given twice
  [1]

An optional argument

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ?guard:None ]
  > EOF
  File "Routes.ml", line 1, characters 61-65:
  Error: ?guard: optional arguments are not supported
  [1]

A route with children

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.route A ~path:"/a" ~page:Pages.a
  >       [ Router.route B ~path:"/b" ~page:Pages.b ];
  >   ]
  > EOF
  File "Routes.ml", lines 3-4, characters 4-49:
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
  Error: the child nodes must be a list such as [ Router.route A ~path:"/a" ~page:Pages.a ]
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
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~prerender:flag ]
  > EOF
  File "Routes.ml", line 1, characters 65-69:
  Error: ~prerender must be true or false
  [1]

A loader that is not a value path

  $ gen <<'EOF'
  > Router.make
  >   [
  >     Router.group ~path:"/a" ~loader:(fun _ -> ())
  >       [ Router.route A ~path:"/" ~page:Pages.a ];
  >   ]
  > EOF
  File "Routes.ml", line 3, characters 36-49:
  Error: ~loader must be a value path such as Loaders.issue; its last name labels the result
  [1]

A page that is not a value path

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:(Pages.page ~x:1) ]
  > EOF
  File "Routes.ml", line 1, characters 46-63:
  Error: ~page must be a value path such as Pages.home
  [1]

A handler that is not a value path

  $ gen <<'EOF'
  > Router.make
  >   [ Router.endpoint A ~path:"/a" ~method_:`GET ~handler:(fun _ -> Handlers.a) ]
  > EOF
  File "Routes.ml", line 2, characters 56-77:
  Error: ~handler must be a value path such as Pages.home
  [1]

A nested Router.make

  $ gen <<'EOF'
  > Router.make [ Router.make [] ]
  > EOF
  File "Routes.ml", line 1, characters 14-28:
  Error: Router.make can only be the root
  [1]

The tree bound as let routes, alone or after items, is valid

  $ gen <<'EOF' > /dev/null
  > let routes = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF

  $ gen <<'EOF' > /dev/null
  > open Shared
  > 
  > let first = 1
  > 
  > let routes =
  >   Router.make [ Router.route A ~path:"/a" ~page:a ]
  > EOF

The bare tree after items ended with ;; is valid too

  $ gen <<'EOF' > /dev/null
  > open Shared
  > let first = 1
  > ;;
  > Router.make [ Router.route A ~path:"/a" ~page:a ]
  > EOF

The tree bound to another name, or with rec, two bindings, a parameter, a
type or an attribute

  $ gen <<'EOF'
  > let () = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-64:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

  $ gen <<'EOF'
  > let tree = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-66:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

  $ gen <<'EOF'
  > let rec routes = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-72:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

  $ gen <<'EOF'
  > let routes = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > and other = 1
  > EOF
  File "Routes.ml", lines 1-2, characters 0-13:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

  $ gen <<'EOF'
  > let routes () = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-71:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

  $ gen <<'EOF'
  > let routes : t = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 0-72:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

  $ gen <<'EOF'
  > let routes = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ] [@@inline]
  > EOF
  File "Routes.ml", line 1, characters 0-79:
  Error: write the tree as let routes = Router.make ...: one binding named routes, with no rec, no parameter, no type and no attribute
  [1]

A bare tree after a let without ;; is an argument of that let

  $ gen <<'EOF'
  > let security = [ ("x-frame-options", "DENY") ]
  > 
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 3, characters 0-11:
  Error: Router.make is read as an argument of the let before it; write let routes = Router.make ...
  [1]

A bare tree after an open without ;; is a syntax error

  $ gen <<'EOF'
  > open Shared
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 2, characters 0-6:
  Error: Syntax error
  [1]

An item after the tree

  $ gen <<'EOF'
  > let routes = Router.make [ Router.route A ~path:"/a" ~page:Pages.a ]
  > let late = 1
  > EOF
  File "Routes.ml", line 2, characters 0-12:
  Error: the route file must end with the route tree, Router.make ... or let routes = Router.make ...; open, let, module and type items go before it
  [1]

A second tree

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ];;
  > Router.make [ Router.route B ~path:"/b" ~page:Pages.b ]
  > EOF
  File "Routes.ml", line 1, characters 0-55:
  Error: the route file holds one route tree, as its last item; this is another expression
  [1]

An empty file

  $ gen < /dev/null
  File "Routes.ml", line 1:
  Error: the route file is empty; it must end with the route tree, Router.make ... or let routes = Router.make ...
  [1]

A search default that names a value defined before the tree

  $ gen <<'EOF'
  > let first_page = 1
  > 
  > let routes =
  >   Router.make
  >     [ Router.route A ~path:"/a" ~page:Pages.a ~search:{ page = default int first_page } ]
  > EOF
  File "Routes.ml", line 5, characters 75-85:
  Error: first_page is defined before the tree; the shared module holds this default and does not see the items before the tree, so write the value with its module path
  [1]

A search default with a module path

  $ gen <<'EOF' > /dev/null
  > let first_page = 1
  > 
  > let routes =
  >   Router.make
  >     [ Router.route A ~path:"/a" ~page:Pages.a ~search:{ page = default int Config.first_page } ]
  > EOF

A syntax error

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a
  > EOF
  File "Routes.ml", line 2, characters 0-0:
  Error: Syntax error: ] expected
  File "Routes.ml", line 1, characters 12-13:
    This [ might be unmatched
  [1]

The root must be Router.make

  $ gen <<'EOF'
  > Router.route A ~path:"/a" ~page:Pages.a
  > EOF
  File "Routes.ml", line 1, characters 0-39:
  Error: the root must be Router.make
  [1]

Valid input, every node kind, exits 0

  $ gen <<'EOF' > /dev/null
  > Router.make ~layout:Layouts.root ~headers:[ ("x", "y") ] ~cache:no_store ~prerender:false
  >   [
  >     Router.group ~path:"/g/:id<Params.id>" ~layout:Layouts.g ~loader:Loaders.load ~guard:Guards.ok
  >       ~not_found:Pages.nf ~error:Pages.err ~search:{ q = optional string } ~prerender:true
  >       [
  >         Router.route A ~path:"/" ~page:Pages.a;
  >         Router.endpoint B ~path:"/b" ~method_:`GET ~handler:Handlers.b;
  >         Router.action C ~path:"/b" ~method_:`POST ~handler:Handlers.c;
  >       ];
  >     Router.redirect ~path:"/x" ~to_:(Temporary "/");
  >   ]
  > EOF

A route named Some

  $ gen <<'EOF'
  > Router.make [ Router.route Some ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name Some is a predefined constructor that the generated code uses; choose another name
  [1]

A route named None

  $ gen <<'EOF'
  > Router.make [ Router.route None ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name None is a predefined constructor that the generated code uses; choose another name
  [1]

A route named true

  $ gen <<'EOF'
  > Router.make [ Router.route true ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-31:
  Error: name true is a predefined constructor that the generated code uses; choose another name
  [1]

A route named false

  $ gen <<'EOF'
  > Router.make [ Router.route false ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-32:
  Error: name false is a predefined constructor that the generated code uses; choose another name
  [1]

A route named ()

  $ gen <<'EOF'
  > Router.make [ Router.route () ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-29:
  Error: name () is a predefined constructor that the generated code uses; choose another name
  [1]

A route named []

  $ gen <<'EOF'
  > Router.make [ Router.route [] ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 27-29:
  Error: name [] is a predefined constructor that the generated code uses; choose another name
  [1]

A route named ::

  $ gen <<'EOF'
  > Router.make [ Router.route (::) ~path:"/a" ~page:Pages.a ]
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

~prefetch takes `Off, `Hover, `Trajectory or `Visible

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a ~prefetch:`Eager ]
  > EOF
  File "Routes.ml", line 1, characters 64-70:
  Error: ~prefetch must be `Off, `Hover, `Trajectory or `Visible
  [1]

  $ gen <<'EOF'
  > Router.make ~prefetch:true [ Router.route A ~path:"/a" ~page:Pages.a ]
  > EOF
  File "Routes.ml", line 1, characters 22-26:
  Error: ~prefetch must be `Off, `Hover, `Trajectory or `Visible
  [1]

~prefetch is for pages: an endpoint, an action and a redirect have none

  $ gen <<'EOF'
  > Router.make [ Router.endpoint A ~path:"/a" ~method_:`GET ~handler:Handlers.a ~prefetch:`Off ]
  > EOF
  File "Routes.ml", line 1, characters 87-91:
  Error: Router.endpoint has no argument ~prefetch; its labelled arguments are ~path, ~method_, ~handler, ~guard, ~cross_origin, ~headers, ~cache, ~prerender
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.action A ~path:"/a" ~method_:`POST ~handler:Handlers.a ~prefetch:`Off ]
  > EOF
  File "Routes.ml", line 1, characters 86-90:
  Error: Router.action has no argument ~prefetch; its labelled arguments are ~path, ~method_, ~handler, ~guard, ~headers, ~cache, ~prerender
  [1]

  $ gen <<'EOF'
  > Router.make [ Router.route A ~path:"/a" ~page:Pages.a; Router.redirect ~path:"/b" ~to_:(Permanent "/a") ~prefetch:`Off ]
  > EOF
  File "Routes.ml", line 1, characters 114-118:
  Error: Router.redirect has no argument ~prefetch; its labelled arguments are ~path, ~to_
  [1]
