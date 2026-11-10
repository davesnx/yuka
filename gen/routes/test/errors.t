Generation errors point into Routes.mlx

  $ gen () { cat > Routes.mlx; mlx-pp Routes.mlx > routes.ast && yuka-routes --shared routes.ast; }
Two pages with the same path shape

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a/:x<int>" page=P.a />
  >     <Route name=B path="/a/:y<string>" page=P.b />
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 4-50:
  Error: path "/a/:y<string>" has the same shape as "/a/:x<int>" (line 3); both answer `GET
  [1]

An endpoint and a page on one path, both GET

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/feed" page=P.a />
  >     <Endpoint name=B path="/feed" method_=`GET handler=H.b />
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 4-61:
  Error: path "/feed" has the same shape as "/feed" (line 3); both answer `GET
  [1]

A redirect answers every method, so it overlaps an action on its path

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Action name=A path="/old" method_=`POST handler=H.a />
  >     <Route path="/old" redirect=(Permanent "/new") />
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 4-53:
  Error: path "/old" has the same shape as "/old" (line 3); both answer every method (a redirect)
  [1]

A group path and a route path give the same shape as another route

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/a">
  >       <Route name=A path="/:x<string>" page=P.a />
  >     </Group>
  >     <Route name=B path="/a/:y<int>" page=P.b />
  >   </Router>
  > EOF
  File "Routes.mlx", line 6, characters 4-47:
  Error: path "/a/:y<int>" has the same shape as "/a/:x<string>" (line 4); both answer `GET
  [1]

A name used twice

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" page=P.a />
  >     <Route name=A path="/b" page=P.b />
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 16-17:
  Error: name A is used twice (first at line 3)
  [1]

A param label used twice in a branch

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/u/:id<string>">
  >       <Route name=A path="/p/:id<int>" page=P.a />
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 25-38:
  Error: label id is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A loader label used twice in a branch

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/u" loader=Loaders.user>
  >       <Route name=A path="/" page=P.a loader=Other.user />
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 45-55:
  Error: label user is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A search field with the name of a param

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/u/:id<string>" page=P.a search={ id = optional int } />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 56-77:
  Error: label id is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A group search field and a route search field with one name

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/u" search={ q = optional string }>
  >       <Route name=A path="/" page=P.a search={ q = many string } />
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 4, characters 45-64:
  Error: label q is used twice in this branch (params, search fields and loader results share one set of labels)
  [1]

A redirect target that names an unknown param

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route path="/i/:id<string>" redirect=(Permanent "/issue/:key") />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 53-66:
  Error: redirect target "/issue/:key" names :key, which is not a param of the path
  [1]

An action with GET

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Action name=A path="/a" method_=`GET handler=H.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 37-41:
  Error: an Action cannot use `GET; use `POST, `PUT, `PATCH or `DELETE
  [1]

An unknown method

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Endpoint name=A path="/a" method_=`TRACE handler=H.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 39-45:
  Error: method_ must be one of `GET, `POST, `PUT, `PATCH, `DELETE
  [1]

A catch-all that is not the last segment

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/docs/:parts<string...>/edit" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-53:
  Error: catch-all :parts in path "/docs/:parts<string...>/edit" must be the last segment
  [1]

A catch-all in a group path

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/docs/:parts<string...>">
  >       <Route name=A path="/" page=P.a />
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-41:
  Error: a Group path cannot hold a catch-all
  [1]

A trailing slash

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a/" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-28:
  Error: path "/a/" has an empty segment or a trailing slash
  [1]

A dot segment

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a/../b" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-32:
  Error: path "/a/../b" has a ".." segment
  [1]

An encoded static segment

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/caf%C3%A9" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-35:
  Error: segment "caf%C3%A9" in path "/caf%C3%A9" holds % ? or #; write segments decoded
  [1]

A path without a leading slash

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-26:
  Error: path "a" must start with /
  [1]

An unknown param type

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a/:x<float>" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-37:
  Error: param :x in path "/a/:x<float>" has type "float"; the types are int, string, string... and a module path
  [1]

A param without a type

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a/:x" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-30:
  Error: param ":x" in path "/a/:x" must be written :name<type>
  [1]

A param name that is a keyword

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a/:type<string>" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-41:
  Error: param "type" in path "/a/:type<string>" is not a lowercase OCaml label
  [1]

A label reserved by the generated code

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" page=P.a search={ with_query = optional string } />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 44-76:
  Error: label with_query is reserved by the generated code
  [1]

A bad search kind

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" page=P.a search={ q = required string } />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 50-65:
  Error: search field q must be optional T, default T value or many T
  [1]

A path that is not a literal

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path=Paths.a page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 23-30:
  Error: path must be a string literal
  [1]

A name that is not a constructor

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name="a" path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-19:
  Error: name must be a constructor such as Issue
  [1]

An unknown node

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Page name=A path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 4-38:
  Error: unknown node <Page>; the nodes are Router, Group, Route, Endpoint and Action
  [1]

An unknown prop

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" page=P.a layout=L.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 44-47:
  Error: <Route> has no prop layout; its props are name, path, page, loader, guard, search, headers, cache, prerender
  [1]

A missing prop

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 4-30:
  Error: <Route> needs the prop page
  [1]

A route with children

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" page=P.a>
  >       <Route name=B path="/b" page=P.b />
  >     </Route>
  >   </Router>
  > EOF
  File "Routes.mlx", lines 3-5, characters 4-12:
  Error: <Route> takes no children
  [1]

A redirect with a name

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" redirect=(Permanent "/b") />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-17:
  Error: <Route> has no prop name; its props are path, redirect
  [1]

prerender that is not a literal

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=A path="/a" page=P.a prerender=flag />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 47-51:
  Error: prerender must be true or false
  [1]

A loader that is not a value name

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Group path="/a" loader=(fun _ -> ())>
  >       <Route name=A path="/" page=P.a />
  >     </Group>
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 28-41:
  Error: loader must be a value name such as Loaders.issue; its last name labels the result
  [1]

A nested Router

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Router />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 4-14:
  Error: <Router> can only be the root
  [1]

No routes binding

  $ gen <<'EOF'
  > let other = 1
  > EOF
  File "Routes.mlx", line 1:
  Error: no let routes = <Router>...</Router>
  [1]

The root must be a Router

  $ gen <<'EOF'
  > let routes = <Route name=A path="/a" page=P.a />
  > EOF
  File "Routes.mlx", line 1, characters 13-48:
  Error: the root must be <Router>
  [1]

Valid input, every node kind, exits 0

  $ gen <<'EOF' > /dev/null
  > let routes =
  >   <Router layout=L.root headers=[ ("x", "y") ] cache=No_store prerender=false>
  >     <Group path="/g/:id<M.Id>" layout=L.g loader=L.load guard=G.ok not_found=P.nf error=P.err
  >       search={ q = optional string } prerender=true>
  >       <Route name=A path="/" page=P.a />
  >       <Endpoint name=B path="/b" method_=`GET handler=H.b />
  >       <Action name=C path="/b" method_=`POST handler=H.c />
  >     </Group>
  >     <Route path="/x" redirect=(Temporary "/") />
  >   </Router>
  > EOF

A route named Some

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=Some path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-20:
  Error: name Some is a predefined constructor that the generated code uses; choose another name
  [1]

A route named None

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=None path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-20:
  Error: name None is a predefined constructor that the generated code uses; choose another name
  [1]

A route named true

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=true path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-20:
  Error: name true is a predefined constructor that the generated code uses; choose another name
  [1]

A route named false

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=false path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-21:
  Error: name false is a predefined constructor that the generated code uses; choose another name
  [1]

A route named ()

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=() path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-18:
  Error: name () is a predefined constructor that the generated code uses; choose another name
  [1]

A route named []

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=[] path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-18:
  Error: name [] is a predefined constructor that the generated code uses; choose another name
  [1]

A route named ::

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route name=(::) path="/a" page=P.a />
  >   </Router>
  > EOF
  File "Routes.mlx", line 3, characters 16-20:
  Error: name :: is a predefined constructor that the generated code uses; choose another name
  [1]

No named node

  $ gen <<'EOF'
  > let routes =
  >   <Router>
  >     <Route path="/a" redirect=(Permanent "/b") />
  >   </Router>
  > EOF
  File "Routes.mlx", line 1:
  Error: Routes.mlx has no named node
  [1]
