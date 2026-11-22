# Router

`Routes.ml` holds the route tree of an app, `Router.make ...`, which is
never compiled: `yuka routes` reads it and writes two modules, the shared
`Routes` and the server `Yuka_routes`. Items before the tree are
allowed; see "Code before the tree".
[`getting-started.md`](getting-started.md) has the dune rules.

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
    Router.get Feed ~path:"/feed.json" ~handler:Api.feed;
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
let post (_ : Yuka.Server.request) ~slug =
  Yuka.Async.return
    (if slug = "hello" then Ok "Hello, world" else Error Yuka.Server.Not_found)
```

## Nodes

- `Router.make [ nodes ]`: the root.
- `Router.group ~path [ nodes ]`: a path prefix for its children. Its
  layout, loader, guard, search fields and rules apply to all of them.
- `Router.route Name ~path ~page`: a page. `?overlay:Pages.dialog` adds
  an overlay page (see "Overlay routes").
- `Router.get Name ~path ~handler`: a response that is not a page, such
  as JSON or a file. It answers `GET` and `HEAD`.
- `Router.post Name ~path ~handler`, and `Router.put`, `Router.patch` and
  `Router.delete` with the same arguments: a handler for that method, for
  a request that changes data. The answer is never cached.
- `Router.redirect ~path ~to_:(Permanent "/")`: a 308 redirect, or
  `Temporary` for a 307. The target can use the params of the path:
  `~to_:(Temporary "/team/:name")`.

These five are the method nodes. Two method nodes can have the same path
when their methods are different, each with its own name. A request with
another method gets `405` with the methods of the path in `allow`.
`Router.endpoint` and `Router.action` were removed: they are build errors
that name the method nodes.

A node name is a constructor, such as `Home`, and gives the link function
`Routes.home`. Each name is used once. These names are build errors:

- `Some` and `None`, which the generated code uses.
- A name whose lowercase form is an OCaml keyword, such as `Type`,
  `Match` or `Effect`.
- `Href`, `Find`, `With_query`, `With_fragment`, `Current`, `Replace` and
  `Push`, which the `Routes` module already defines.

## Paths

- `:id<string>`: one segment, as a `string`.
- `:page<int>`: an `int`. Only the form `Int.to_string` writes matches, so
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
- `decode` gets the segment after percent-decoding and after the `~` of
  an empty or dot value is removed (see [Links](#links)). When it returns
  `None`, the path does not match and the answer is the not-found page.
- `encode` must be the inverse of `decode`. The router percent-encodes its
  result, so it can return any text.
- `Yuka.Router.Param.int`, `string` and `bool` decode and encode as the
  built-in types do, so you can build on them:
  `~decode:(fun segment -> Yuka.Router.Param.(decode int) segment)`.
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

`optional T` gives a `T option`, `default T fallback` gives a `T` (`fallback` when the
param is absent), and `many T` gives a `T list`. `T` is `string`, `int`,
`bool` or your own type with its module path, as in a path. A value that
does not decode counts as absent. Search fields go on a route or a group.

## Attachments

Each attachment is a value path such as `Pages.home`, or `home` after
`open Pages` (see "Code before the tree"). The generated code
calls it with labelled arguments. `req` is a `Yuka.Server.request`: read
it with `Yuka.Server.Request` (see "The request" in `data.md`). Code that
needs the request of the server gets it from the adapter:
`Yuka_dream.request req` gives a `Dream.request option`.

| Attachment | On | Shape |
|---|---|---|
| `~page` | route | `~params ~search ~loaded () -> Yuka.Server.page` |
| `?overlay` | route | as `~page` |
| `~layout` | make, group | `~params ~loaded ~children () -> Yuka.server Yuka.element` |
| `~loader` | group, route | `req -> ~params -> ('a, Yuka.Server.stop) result Yuka.Async.t` |
| `~guard` | all but redirect | `req -> ~params -> (unit, Yuka.Server.stop) result Yuka.Async.t` |
| `~handler` | method nodes | `req -> ~params -> Yuka.Server.response Yuka.Async.t` |
| `~not_found` | make, group | `~params ~path () -> Yuka.Server.page` |
| `~error` | make, group | `~params () -> Yuka.Server.page` |

- `~params` are the path params of the node and the groups above it. A
  layout gets those of its group, and a client navigation keeps it only
  while they do not change.
- `~loaded` are the loader results. Each result is labelled with the last
  name of the loader: `~loader:Loaders.post` gives `~post`. A layout gets
  the results of the loaders on its group and above.
- Params, search fields and loader results share one set of labels: a
  name used twice is an error. `href`, `fragment`, `with_query`,
  `with_fragment`, `req` and `children` are reserved labels.
- A stop is `Not_found`, `Forbidden` (403), `Redirect`,
  `Redirect_off_site` or `Fail`.
- `not_found` and `error` use the nearest one above the node. A
  `not_found` or `error` below a layout that takes a loader result is an
  error.

Rules, on any node except a redirect. `Router.post`, `Router.put`,
`Router.patch` and `Router.delete` take no `~cache` and no `~prerender`:

- `~headers:[ ("x-frame-options", "DENY") ]`: response headers. A node
  replaces a header of the same name set above it.
- `~cache`: `no_store`, `no_cache`, `private_cache ~max_age:5`,
  `public ~max_age:60 ()` (with an optional `~s_max_age`) or
  `immutable`. The nearest one wins.
- `~prerender:true`: the prerender step can write the page as a static
  file (see `Yuka.Server.Prerender`).
- `~cross_origin:true`, on `Router.post`, `Router.put`, `Router.patch` and
  `Router.delete` only: skip the origin check that these methods get. Use
  it for webhooks.
- `~prefetch`, on make, group and route only: when the browser loads the
  page before the click (see "Prefetch").

## Code before the tree

Items before the tree (`open`, `let`, `module`, `type`) go, as written,
to the top of the server module `Yuka_routes`. A file with items binds
the tree as `let routes = Router.make ...`:

```ocaml
open Pages

let week = Yuka.Server.public ~max_age:604800 ()
let security = [ ("x-frame-options", "DENY") ]

let routes =
  Router.make ~not_found ~error ~headers:security
    [
      Router.route Home ~path:"/" ~page:home;
      Router.route About ~path:"/about" ~page:about ~cache:week;
    ]
```

`~not_found` is `~not_found:not_found`. `let routes` is the tree, not a
value: it is not copied. `Yuka.Server` is opened only inside `~cache`, so
an item writes `Yuka.Server.public`, or opens `Yuka.Server`. Error messages from the compiler
for these items point to the same line in `yuka_routes.ml` as in
`Routes.ml`.

Two limits:

- The shared `Routes` module, which the browser also builds, does not get
  the items. A param type and a search default must still use a module
  path that the shared library sees: `:tab<Model.tab>`,
  `default int Config.first_page`. A default that names a `let` of the
  items is a build error.
- The generated server code binds the params, search fields and loader
  results of a route, and `req`, `children`, `path`, `rules_N`, `layer_N`
  and `fallback_N`. A one-name attachment with one of these names is a
  build error: with `~loader:Loaders.issue`, write `~page:Pages.issue`,
  not `~page:issue`.

## Links

The shared `Routes` module has one function for each route and method
node, named as the node in lowercase:

```ocaml
Routes.hello ~name:"Yuka" ()            (* "/hello/Yuka" *)
Routes.blog ~tag:"ocaml" ~page:2 ()     (* "/blog?tag=ocaml&page=2" *)
Routes.blog ()                          (* "/blog" *)
Routes.blog ~page:2 ~fragment:"top" ()  (* "/blog?page=2#top" *)
```

Path params are required labelled arguments. Search fields are optional
arguments. Every function ends with `()`. A missing or wrong param does
not compile.

Each path param value gives a link, also `""`, `"."` and `".."`, which no
URL segment can hold: browsers resolve dot segments and the server drops
empty ones. Such a value, also after one or more `~`, gets one more `~`
in front, and `find` removes it: `Routes.post ~slug:"" ()` gives
`"/blog/~"`, `~slug:".."` gives `"/blog/~.."` and `~slug:"~"` gives
`"/blog/~~"`. Other values, such as `"~a"`, stay as they are. A
catch-all with no element raises `Invalid_argument`.

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

A navigation to another URL adds a history entry. A navigation to the URL
shown (the fragment does not count), for example a click on the link of
the current page or the reload after a form succeeds, replaces the current
entry, as the browser does. So Back goes to the page before.

To replace the current entry also for another URL, use
`Yuka.Browser.navigate ~replace:true url`, or give the link a
`data-yuka-replace` attribute:

```ocaml
<a href=(Routes.blog ~tag:"bug" ()) data_yuka_replace="">(Yuka.text "Bugs")</a>
```

Without client navigation, `~replace:true` does `location.replace`, so
the full page load also replaces the entry. On a page with no island, a
link with `data-yuka-replace` is a plain link and adds an entry.

A client navigation scrolls to the top of the new page, or to the
element of the URL fragment. For a filter or a tab that loads a new page
from the server, keep the scroll position: use
`Yuka.Browser.navigate ~keep_scroll:true url`, or give the link a
`data-yuka-keep-scroll` attribute:

```ocaml
<a href=(Routes.blog ~tag:"bug" ()) data_yuka_keep_scroll="">(Yuka.text "Bugs")</a>
```

The page does not scroll to the top or to the fragment. The focus and
the announcer change as for other navigations. You can use both
attributes on one link. Without client navigation, the full page load
scrolls as the browser does.

A form with `method="get"` (or with no method) is also a client
navigation. When the user submits it, Yuka makes the URL from the action
of the form and its fields, as the browser does, and loads that URL as a
click on a link does. A search form in the layout thus keeps the islands
of the layout:

```ocaml
<form method_=`get action=(Routes.blog ()) role=`search>
  <input type_=`search name="q" />
</form>
```

The `formmethod`, `formaction` and `formtarget` attributes and the name
and value of the submit button count. Yuka does not change a submit that
is already prevented (for example by `Yuka.Form`), a form with a
`target` other than `_self`, a form with an action URL on another
origin, or a form with a `data-yuka-reload` attribute: these do a full
page load or what the browser does. While the navigation is in flight,
the form has a `data-yuka-pending` attribute, as a clicked link has.

After an `Action.call`, the server-rendered parts of the page can show
old data. `Yuka.Browser.refresh ()` loads the URL shown again from the
server, with no cached answer, and puts in the new content:

```ocaml
Yuka.Async.on_result (Yuka.Action.call Actions.close_issue issue.id) (function
  | Ok (Ok ()) -> Yuka.Browser.refresh ()
  | Ok (Error _) | Error _ -> ())
```

The refresh replaces the current history entry, so Back does not change.
The page does not scroll, and the announcer does not change. The focus
stays on the focused element when it is still in the page. Else it goes
to the new element with the same `id`, or else to the new element at the
same place with the same tag. When there is no such element, the focus
moves as for other navigations. A form success with no redirect and no
`on_ok` calls `Yuka.Browser.refresh ()`. Without client navigation, the
refresh is a full page load of the URL shown.

`Yuka.Browser.navigating` is a read-only State: `true` from the click
until the new page is shown (or a full page load starts in its place). An
island can read it to show a progress bar:

```ocaml
let[@client] make () =
  <div class_=(if State.get Yuka.Browser.navigating then "progress on" else "progress") />
```

It is also `true` during `Yuka.Browser.refresh ()`, until the new
content is shown. It is always `false` on the server.

`Yuka.Browser.navigation` is a read-only State that tells which
navigation is in flight. It is `Some` for the same time as `navigating`
is `true`, else `None`. The value has three fields:

- `url`: the target. For a URL of the page origin, it is the path and
  the query (the fragment does not count). Else it is the full URL.
- `from`: the path and the query of the page shown when the navigation
  started.
- `kind`: `` `Push `` adds a history entry. `` `Replace `` replaces the
  current entry (`navigate ~replace:true`, a link with
  `data-yuka-replace`, or a navigation to the URL shown). `` `Traverse ``
  is Back or Forward. `` `Reload `` is `Yuka.Browser.refresh ()`.

A newer navigation replaces the value. To show no progress bar for a
refresh:

```ocaml
let[@client] make () =
  <div
    class_=(match Yuka.State.get Yuka.Browser.navigation with
            | Some { Yuka.Browser.kind = `Reload; _ } | None -> "progress"
            | Some _ -> "progress on") />
```

`Routes.pending ()` gives the target as a typed route; see
[The current route](#the-current-route).

The link that the user clicked has a `data-yuka-pending` attribute while
its navigation is in flight. Use it in CSS to show a spinner on that
link:

```css
a[data-yuka-pending]::after { content: ""; /* a spinner */ }
```

Yuka removes the attribute when the new page (or the first part of a
streamed page) is shown, when the navigation fails or becomes a full page
load, and when a newer navigation starts. `aria-current` changes only
after the new page is shown. Yuka does not set `aria-busy` on the link,
because `aria-busy` tells assistive technology that the content of the
element changes, and the content of the link does not change. For
assistive technology, Yuka announces the title of the new page.

A page with a `Yuka.Await` streams on a client navigation as on a first
load. The server waits for each `Await` as its `blocking` says (by
default 100 ms; see [Data](data.md#values-that-load-await)). When every
value settles in time, the new page comes in one piece. When one does
not, the new page is shown at once with the `loading` content of each
pending `Await`, and `navigating` becomes `false`. Each `Await` then replaces
its `loading` content when its value comes, and its islands start. An
island that holds a pending `Await` starts after that `Await` is filled.
The title, focus, scroll and announcer change when the new page is shown,
not with each fill. A newer navigation stops the fills of the page it
replaces. A page whose `Cache-Control` is shared (`public` or `s-maxage`)
does not stream, on a client navigation or a first load: the server waits
for every `Await` and sends the settled page, so a `Live.make` in a late
fill still sends it with `private, no-store`. On Back or Forward, the
page first gets the fills that the navigation cache holds, then scrolls
to its saved position. It scrolls to that position again after each
fill that comes later, until the user scrolls, touches, clicks or types,
or the stream ends. A URL fragment whose element comes in a later fill
is scrolled to by the same rule.

After a client navigation to another page, Yuka tells screen readers
about it and moves the focus, as a full page load does:

- A live region (`<div id="yuka-announcer" aria-live="assertive">`,
  hidden from view) gets the new `document.title`, or the text of the
  first `h1` of the new content when the title is empty.
- The focus goes to the first of these in the new content (the outlet,
  or `<body>` without one) that can take it: an element with
  `autofocus`, the element of the URL fragment, the first `h1`, the
  content itself, then its elements in document order. An `h1` or a wrapper with no `tabindex` gets
  `tabindex="-1"`. The page does not scroll for it.
- The focus does not move when an island of the new content took it, or
  when it is in an `input`, `textarea`, `select` or `contenteditable`
  element, so a search field that navigates keeps it.

`Routes.replace`, `Routes.push`, `Browser.replace_url`, a fragment link,
and Back or Forward to an entry of the page shown change neither.

## Overlay routes

A route with `?overlay` shows its overlay page over the current page on a
client navigation, as a dialog. A direct load or a reload of its URL
shows the normal page:

```ocaml
(* Routes.ml *)
Router.group ~path:"/" ~layout:Pages.shell
  [
    Router.route Issues ~path:"/" ~page:Pages.index;
    Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue
      [ Router.route Issue ~path:"/" ~page:Pages.issue ?overlay:Pages.issue_dialog ];
  ]

(* pages.mlx: the overlay page gets the arguments of ~page *)
let issue_dialog ~id ~issue () =
  Yuka.Server.page ~title:id (fun () ->
      <div class_="dialog" role=`dialog aria_label=id>
        <Yuka.Client><Close_button /></Yuka.Client>
        <Issue_view issue />
      </div>)

(* close_button.mlx *)
let[@client] make () =
  <button type_=`button on_click=(fun _ -> Yuka.Browser.back ())>"Close"</button>
```

- A click on a link, or `Yuka.Browser.navigate`, to the route sends
  `Yuka-Overlay: 1`. When the current page and the route share a layout
  that stays (the case for an outlet answer), the server renders the
  overlay page inside the layouts of the route and answers its content
  with `Yuka-Layer: overlay`. Else it answers as for any page.
- The browser puts that content in one `<yuka-overlay>` element at the
  end of `<body>` and adds a history entry. The page under it stays as it
  is: its islands run, and its scroll does not change. The title and
  `Routes.current` are those of the overlay route. The focus moves into
  the overlay, as for a client navigation.
- Back removes the overlay with no request and gives the title, the
  route and the focus back to the page under it. Forward shows the
  overlay again.
- A link in the overlay to another route with an overlay replaces the
  overlay. Any other navigation removes it.
- `Yuka.Browser.back ()` closes the overlay: Back when the history entry
  before it is the page under it, else a client navigation to the URL of
  that page.
- The overlay page is the whole content of the overlay: give it its own
  backdrop and dialog markup. Ids in it start with `overlay-`.

Page answers have `Vary: Yuka-Navigate, Yuka-Prefetch, Yuka-Overlay`.

### Split views

There are no parallel outlets. For a list next to its detail, put the
list in the layout of a group and the detail in a child route: a client
navigation between details keeps the layout. For a second pane with its
own state, keep that state in a search field and change it with
`Routes.replace`, or keep it in an island.

## The current route

The shared `Routes` module also has four functions for the route of the
page that is shown and of the page that loads:

```ocaml
val current : unit -> t option Yuka.State.read
val pending : unit -> t option Yuka.State.read
val replace : t -> unit
val push : t -> unit
```

`Routes.current ()` gives the route of the page as a read-only State,
on the server and in an island. It is `None` when the URL matches no page
route, and in a tree that `Yuka.render ~root` builds. Call it in the body of
a component and read the State in a hole. A client navigation sets the
State, also in an island of a layout that stays on the screen.

`Routes.pending ()` gives the target of the client navigation in flight
(`Yuka.Browser.navigation`) as a read-only State. It is `None` when no
navigation is in flight, when the target matches no page route, and on
the server. When the new page is shown, it becomes `None` and
`Routes.current` gives the new route. Use it to mark the link of the
target while the page loads:

```ocaml
let[@client] make () =
  let pending = Routes.pending () in
  <a href=(Routes.href Routes.Issues)
     class_=(match Yuka.State.get pending with Some Routes.Issues -> "loading" | _ -> "")>
    (Yuka.text "Issues")
  </a>
```

`Routes.replace route` and `Routes.push route` change the route of the page
that is shown with no request: the URL (`history.replaceState` or
`history.pushState`) and the State, so every island that reads
`Routes.current` shows the new route. After `push`, Back and Forward set the
State again with no request. A route of another page (another node, or
another path param) is a client navigation: `Routes.replace` replaces the
current history entry, as `Yuka.Browser.navigate ~replace:true`, and
`Routes.push` adds an entry, as `Yuka.Browser.navigate`. So a search field
that calls `Routes.replace` on each key adds no entries.
A reload loads the new URL, and the server renders the page with it.

To keep the state of a page in its URL, such as a filter that a user can
share, give the state to the page as search fields and write it back with
`Routes.replace`:

```ocaml
(* Routes.ml *)
Router.route Blog ~path:"/" ~page:Pages.blog ~search:{ tag = optional string }

(* pages.mlx: the island gets the search field as a prop *)
let blog ~tag () =
  Yuka.Server.page ~title:"Blog" (fun () ->
      <Yuka.Client><Posts tag=(Option.value tag ~default:"") /></Yuka.Client>)

(* posts.mlx *)
let[@client] make ~(tag : string) () =
  let tag = Yuka.State.make tag in
  Yuka.Effect.on_change tag (fun ~prev:_ ~next ->
      Routes.replace (Routes.Blog { tag = (if next = "" then None else Some next) }));
  ...
```

Another island on the page can read the tag with `Routes.current`:

```ocaml
let[@client] make () =
  let route = Routes.current () in
  <span>
    (match Yuka.State.get route with
     | Some (Routes.Blog { tag = Some t }) -> Yuka.text t
     | _ -> Yuka.text "all")
  </span>
```

`Yuka.Browser.replace_url` changes the URL only: islands that read
`Routes.current` do not see the change.

The framework writes the route into the HTML of each page with an island
(about 70 bytes), and at the start of each client navigation answer that
replaces the inside of a layout.

## Prefetch

A client navigation can load a page before the click: a prefetch.
`~prefetch` on `Router.make`, a group or a route sets when it starts:

| Value | The request starts |
|---|---|
| `` `Off `` | only at the click |
| `` `Hover `` | 50 ms after the pointer or the focus is on the link, and at once on a press |
| `` `Trajectory `` (default) | also when the mouse moves toward the link |
| `` `Visible `` | also when the link comes within 200 px of the view |
| `` `Idle `` | also when the page is loaded and the browser is idle |

Each level includes the ones before it. The nearest `~prefetch` wins, as
for `~cache`. A method node and a redirect take no `~prefetch`;
another value is an error.

`` `Idle `` needs a `~cache` with a max-age: a prefetched answer without one
can be used for 10 s only. `yuka routes` reports an error when the nearest
`~cache` of a route with `` `Idle `` is absent, `no_store` or `no_cache`;
it accepts a `~cache` that names a `let`. The server counts a route with
`` `Idle `` as `` `Visible `` when the `Cache-Control` of its answers has
no max-age above 0: the one in `~headers` when there is one, else the
`~cache` rule. A page that renders a `Live.make` is sent with
`private, no-store` at render time, which the level cannot know: do not
give such a route `` `Idle ``.

With `` `Trajectory `` the browser follows the mouse pointer (not touch or
pen). Every 50 ms or more it takes the smoothed direction of the movement
and finds the visible link on screen that the pointer moves toward. When
the same link is found twice in a row, it is prefetched before the pointer
is on it. This prefetch does not load the island chunks and style sheets of
the page; a later hover, focus or press on the link does. On a page whose
highest level is `` `Trajectory ``, the navigation code loads at the first
mouse movement; with `` `Visible `` or `` `Idle `` it loads when the page
starts.

With `` `Idle ``, when the page starts and after each client navigation or
action, the browser waits until it is idle (`requestIdleCallback`). Then
it takes the links of the page in document order, one for each URL,
without the URLs that are in the cache or in flight and those refused below
`idle`, and puts at most 15 of them in the queue. An idle prefetch has
`Yuka-Prefetch: idle` and `priority: "low"`, starts only while fewer than
4 prefetches are in flight and after every waiting visible link, and does
not load the island chunks and style sheets. There is no idle pass, and no
waiting idle link starts, under `saveData`, on a `2g` or `slow-2g`
connection, or while the document is hidden; a pass that finds the document
hidden runs once when the document becomes visible, and the waiting idle
links start then. A link to the URL on screen is skipped.

```ocaml
Router.make ~not_found
  [
    Router.route Home ~path:"/" ~page:home;
    Router.group ~path:"/docs" ~prefetch:`Visible [ Router.route Doc ~path:"/:slug<string>" ~page:doc ];
    Router.route Export ~path:"/export" ~page:export ~prefetch:`Off;
  ]
```

The browser does not have the route tree. Each page carries the highest
level of the tree (`<meta name="yuka-prefetch" content="visible">`, no
meta for `` `Trajectory ``), and the browser runs the triggers up to that
level. A prefetch request has the header `Yuka-Prefetch: hover` (hover,
focus or press), `trajectory`, `visible` or `idle`.
When the trigger is above the level of the route, the server answers `204`
with `Yuka-Prefetch: LEVEL` (`off`, `hover`, `trajectory` or `visible`) before guards
and loaders run. The browser keeps no
answer for that URL, and for the life of the page it sends no prefetch
above that level for it (it keeps at most 200 URLs). A click always loads
the page. So an app that mixes levels pays one small refused request for
each URL of a route with a lower level, once per page load. With
`` `Visible `` or `` `Idle `` somewhere in the tree, every page observes its
links and pays one refused request for each URL of a route with a lower
level. The server counts a value it does not know as
`visible`. A prefetch of a method node gets `204` with
`Yuka-Prefetch: off`, and its guards and handler do not run. A prefetch
of a static file (a public directory, `/_yuka/app/`, `/_yuka/css/`) gets
`204` with `Yuka-Prefetch: off`, and the file is not read. Page answers have `Vary: Yuka-Navigate, Yuka-Prefetch, Yuka-Overlay`.

On a link, `data-yuka-prefetch="off"` stops its prefetch.
`navigator.connection.saveData` stops all prefetch.

`Yuka.Browser.prefetch url` prefetches a URL that no link shows yet, for
example the next item of a list with keyboard navigation. It is a hover
prefetch (`Yuka-Prefetch: hover`) with the same rules: no request when the
highest level is `` `Off ``, under `saveData`, when the server refused
`hover` or a lower level for the URL before, or when the cache holds an
answer or a request for the URL. A client navigation to the URL then uses
the answer with no second request. When the navigation code is not loaded
yet, the call loads it. Without client navigation, and for a URL of
another origin, it does nothing.

```ocaml
let on_key ~next event =
  match Yuka.Event.key event with
  | "ArrowDown" -> Yuka.Browser.prefetch (Routes.href (Routes.Doc { slug = next }))
  | _ -> ()
```

A page with no island loads no navigation code, so the browser prefetches
for it. At the end of the body of such a page, the server prints one
speculation rule (JSON, not JavaScript):

```html
<script type="speculationrules">{"prefetch":[{"where":{"and":[{"href_matches":"/*"},{"not":{"selector_matches":"[data-yuka-prefetch=off],[download],[target]"}}]},"eagerness":"conservative"}]}</script>
```

A browser that runs speculation rules (Chrome and Edge today; a browser
that does not ignores the element) fetches the full document of a link to this site at the
pointer down or touch down on it, on desktop and on mobile, and uses that
answer at the click that follows. A hover alone fetches nothing. A link
with `data-yuka-prefetch="off"`, `download` or `target` is left out. With
the highest level of the tree `` `Off ``, no page has the rule. A page with
an island and a client navigation answer have none. The not-found and error
pages have it when they have no island.

Such a request is a navigation prefetch: `Sec-Purpose: prefetch` and
`Sec-Fetch-Dest: document`. A prerender has `Sec-Purpose: prefetch;prerender`,
and the server reads it as a prefetch. The server counts a navigation prefetch as the trigger `hover`
(which includes a press): a page route with `` `Off `` and a method node
answer `503` with `Cache-Control: no-store` and `Vary:
Yuka-Navigate, Yuka-Prefetch, Sec-Purpose`, before guards, loaders and the
handler. The browser drops a non-2xx answer and loads the URL again at the
click. Any other page route answers the full page. A static file is served,
because the click follows the press at once and needs the file. A request
with `Sec-Purpose` and another `Sec-Fetch-Dest` (such as `empty`, which
browsers send for `<link rel="prefetch">`) is answered as a request without
`Sec-Purpose`. Each refused prefetch shows as a `503` in the access log. To
allow the rule under a `Content-Security-Policy`, see
[Security](security.md).

A prefetch runs the guards and loaders of the page for a link that the
user may never click: they must have no side effects.

## Limitations

- After `Routes.push`, Back and Forward set the route only when client
  navigation is on (`Yuka.render ~islands ()` without `~navigation:false`).
- There is no base path: the app is served at the root of its origin.
- An editor does not check `Routes.ml`. `yuka routes` reports each error
  with its location:

```
File "Routes.ml", line 3, characters 28-45:
Error: param :id in path "/post/:id<uuid>" has type "uuid"; the types are int, string, string... and a type with its module path, such as Model.issue_id
```
