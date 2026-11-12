# Router

`Routes.ml` is the route tree of an app. It holds one expression,
`Router.make ...`, with no `open` and no `let`. It is never compiled:
`yuka routes` reads it and writes two modules, the shared `Routes` and the
server `Routes_server`. [`getting-started.md`](getting-started.md) has the
dune rules.

```ocaml
Router.make ~not_found:Pages.not_found ~error:Pages.error
  [
    Router.route Home ~path:"/" ~page:Pages.home;
    Router.route Hello ~path:"/hello/:name<string>" ~page:Pages.hello;
    Router.group ~path:"/blog" ~layout:Pages.blog_layout
      [
        Router.route Blog ~path:"/" ~page:Pages.blog
          ~search:{ tag = optional string; page = default int 1 };
        Router.route Post ~path:"/:slug<string>" ~page:Pages.post
          ~loader:Loaders.post;
      ];
    Router.endpoint Feed ~path:"/feed.json" ~method_:`GET ~handler:Api.feed;
    Router.redirect ~path:"/old-blog" ~to_:(Permanent "/blog");
  ]
```

Some of the functions it names, in the server library. A page gets its
path params, search fields and loader results:

```ocaml
(* pages.mlx *)
let blog ~tag ~page () =
  Yuka.Server.page ~title:"Blog" (fun () ->
      <a href=(Routes.blog ?tag ~page:(page + 1) ())>"Next page"</a>)

let post ~slug ~post () =
  Yuka.Server.page ~title:slug (fun () -> <article>(Yuka.text post)</article>)

(* loaders.ml *)
let post (_ : Dream.request) ~slug =
  Yuka.Async.return
    (if slug = "hello" then Ok "Hello, world" else Error Yuka.Server.Not_found)
```

## Nodes

- `Router.make [ nodes ]`: the root.
- `Router.group ~path [ nodes ]`: a path prefix for its children. Its
  layout, loader, guard, search fields and rules apply to all of them.
- `Router.route Name ~path ~page`: a page.
- `Router.endpoint Name ~path ~method_ ~handler`: a response that is not
  a page, such as JSON or a file.
- `Router.action Name ~path ~method_ ~handler`: like an endpoint, for a
  method that changes data. `` `GET `` is an error, and the answer is
  never cached.
- `Router.redirect ~path ~to_:(Permanent "/")`: a 308 redirect, or
  `Temporary` for a 307. The target can use the params of the path:
  `~to_:(Temporary "/team/:x")`.

`method_` is one of `` `GET ``, `` `POST ``, `` `PUT ``, `` `PATCH `` and
`` `DELETE ``. A `` `GET `` node also answers `HEAD`.

## Paths

- `:id<string>`: one segment, as a `string`.
- `:n<int>`: an `int`. Only the form `Int.to_string` writes matches, so
  `01` and `+1` do not.
- `:tab<Model.tab>`: your own type, written with its module path. See
  below.
- `:parts<string...>`: a catch-all, the last segment of a route path, as
  a `string list` with one element or more. A group path cannot have one.

### Your own param types

The name between `<` and `>` can be your own type, written with its
module path. The router finds the value that decodes and encodes it by
the rule of codecs: a type `foo` uses `foo_param`, a
`Yuka.Router.Param.t`.

```ocaml
(* shared/model.ml *)
type tab = Overview | Activity

let tab_param =
  Yuka.Router.Param.make
    ~decode:(function
      | "overview" -> Some Overview | "activity" -> Some Activity | _ -> None)
    ~encode:(function Overview -> "overview" | Activity -> "activity")
```

```ocaml
Router.route Issue ~path:"/issue/:id<string>/:tab<Model.tab>" ~page:Pages.issue
```

`Issue_id.t` uses `Issue_id.param`: with `type t = int` and `let param = ...` in
`issue_id.ml`, write `:id<Issue_id.t>`.

- The page gets the decoded value: `Pages.issue ~id ~tab ()` with
  `tab : Model.tab`.
- The link function takes the same type:
  `Routes.issue ~id:"YUK-8" ~tab:Activity ()` gives
  `"/issue/YUK-8/activity"`.
- `decode` gets the segment after percent-decoding. When it returns
  `None`, the path does not match and the answer is the not-found page.
- `encode` must be the inverse of `decode`. The router percent-encodes its
  result, so it can return any text.
- `Yuka.Router.Param.int`, `string` and `bool` decode and encode as the
  built-in types do, so you can build on them:
  `~decode:(fun s -> Yuka.Router.Param.(decode int) s)`.
- The type and its value must be in the shared library, because the
  browser builds links too.
- Write the module path: the generated `Routes` module opens nothing, so
  `:tab<tab>` is a build error. So is a module (`:tab<Model>`; write
  `:tab<Model.t>`) and a type with a parameter (`int list`).
- When the value is missing, the build fails with
  `Unbound value Model.tab_param` in the generated `routes.ml`.

## Search params

```ocaml
~search:{ tag = optional string; page = default int 1; tab = optional Model.tab }
```

`optional T` gives a `T option`, `default T d` gives a `T` (`d` when the
param is absent), and `many T` gives a `T list`. `T` is `string`, `int`,
`bool` or your own type with its module path, as in a path. A value that
does not decode counts as absent. Search fields go on a route or a group.

## Attachments

Each attachment is a value path such as `Pages.home`. The generated code
calls it with labelled arguments. `req` is the request of the server
adapter, such as `Dream.request`.

| Attachment | On | Shape |
|---|---|---|
| `~page` | route | `~params ~search ~loaded () -> Yuka.Server.page` |
| `~layout` | make, group | `~loaded ~children () -> Yuka.server Yuka.element` |
| `~loader` | group, route | `req -> ~params -> ('a, Yuka.Server.stop) result Yuka.Async.t` |
| `~guard` | all but redirect | `req -> ~params -> (unit, Yuka.Server.stop) result Yuka.Async.t` |
| `~handler` | endpoint, action | `req -> ~params -> Yuka.Server.response Yuka.Async.t` |
| `~not_found` | make, group | `~params ~path () -> Yuka.Server.page` |
| `~error` | make, group | `~params () -> Yuka.Server.page` |

- `~params` are the path params of the node and the groups above it.
- `~loaded` are the loader results. Each result is labelled with the last
  name of the loader: `~loader:Loaders.post` gives `~post`. A layout gets
  the results of the loaders on its group and above.
- Params, search fields and loader results share one set of labels: a
  name used twice is an error.
- A stop is `Not_found`, `Forbidden` (403), `Redirect`,
  `Redirect_off_site` or `Fail`.
- `not_found` and `error` use the nearest one above the node. A
  `not_found` or `error` below a layout that takes a loader result is an
  error.

Rules, on any node except a redirect:

- `~headers:[ ("x-frame-options", "DENY") ]`: response headers. A node
  replaces a header of the same name set above it.
- `~cache`: `no_store`, `no_cache`, `private_ ~max_age:5`,
  `public ~max_age:60 ()` (with an optional `~s_max_age`) or
  `immutable`. The nearest one wins.
- `~prerender:true`: the prerender step can write the page as a static
  file (see `Yuka.Server.Prerender`).
- `~cross_origin:true`, on an endpoint only: skip the origin check that a
  method other than `GET`, `HEAD` and `OPTIONS` gets. Use it for webhooks.

## Links

The shared `Routes` module has one function for each route, endpoint and
action, named as the node in lowercase:

```ocaml
Routes.hello ~name:"Yuka" ()            (* "/hello/Yuka" *)
Routes.blog ~tag:"ocaml" ~page:2 ()     (* "/blog?tag=ocaml&page=2" *)
Routes.blog ()                          (* "/blog" *)
Routes.blog ~page:2 ~fragment:"top" ()  (* "/blog?page=2#top" *)
```

Path params are required labelled arguments. Search fields are optional
arguments. Every function ends with `()`. A missing or wrong param does
not compile.

The last optional argument, `?fragment`, adds `#` and the encoded
fragment; `~fragment:""` adds `#` alone. A param, search field or loader
named `fragment` is a build error. The server never receives the fragment,
and Yuka gives an island no way to read it.

`Routes.t` has one constructor for each named node. `Routes.href` turns
one into a URL, and `Routes.find` reads a method, the path segments and
the query pairs:

```ocaml
Routes.href (Routes.Hello { name = "Yuka" })   (* "/hello/Yuka" *)
Routes.find `GET [ "hello"; "Yuka" ] []        (* Found (Hello { name = "Yuka" }) *)
```

`find` gives `Found`, `Wrong_method`, `Redirect` or `Missing`, all in
`Yuka.Router`.

## Navigation in the browser

On a page with an island, `Yuka.render ~islands ()` makes a click on a
link on the same site load the new page without a full page load. On a
page with no island, links load full pages. In an island,
`Yuka.Browser.navigate` does the same as a click:

```ocaml
on_click=(fun _ -> Yuka.Browser.navigate (Routes.blog ~tag:"bug" ()))
```

## Limitations

- An island cannot read the current route or search params as a State.
  Pass what it needs as props.
- There is no base path: the app is served at the root of its origin.
- An editor does not check `Routes.ml`. `yuka routes` reports each error
  with its location:

```
File "Routes.ml", line 3, characters 28-45:
Error: param :id in path "/post/:id<uuid>" has type "uuid"; the types are int, string, string... and a type with its module path, such as Model.issue_id
```
