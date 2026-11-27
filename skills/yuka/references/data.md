# Data

This page explains how a page reads and changes data on the server:
actions, forms, remote data and live data, and how to show a value that
loads. The samples come from Yuka's Mini Linear demo
(`demo/mini-linear/shared` and `demo/mini-linear/server/handlers.ml`). The
exact API is in
[`src/yuka.mli`](https://github.com/davesnx/yuka/blob/main/src/yuka.mli),
[`src/form.mli`](https://github.com/davesnx/yuka/blob/main/src/form.mli),
[`src/remote.mli`](https://github.com/davesnx/yuka/blob/main/src/remote.mli)
and [`src/live.mli`](https://github.com/davesnx/yuka/blob/main/src/live.mli).

Each kind of data has two parts with one name:

- The declaration, in the shared library: its name and the codecs of its
  input and output. The server and the browser both compile it.
- The implementation, in the server: `Yuka.Server.Action.implement`,
  `Yuka.Server.Form.implement` or `Yuka.Server.Live.implement`.

## Async values

`'a Yuka.Async.t` is a value that may not be ready yet. The server and the
browser use the same type. Loaders, guards, handlers and actions give an
`Async`, and `<Yuka.Await>` shows one.

An `Async` has one of three statuses:

- `Pending`: the value is not ready.
- `Done value`: the value is ready.
- `Failed message`: the work failed. A failure is a value with a message,
  not an exception.

An `Async` settles one time. When it is `Done` or `Failed`, a later
resolve or fail does nothing.

To make an `Async`:

- `Yuka.Async.return value` gives one that is `Done`.
- `Yuka.Async.failed message` gives one that is `Failed`.
- `Yuka.Async.make ()` gives one that is `Pending`, with the functions
  that resolve and fail it. Use it to wrap an API that takes callbacks.

`Yuka.Async.map` and `Yuka.Async.bind` change the value when it is
`Done`. A failure keeps its message. When the function raises, the result
is `Failed` with the exception as text:

```ocaml
let title = Yuka.Async.map (fun (issue : Model.Issue.t) -> issue.title) issue
```

To read an `Async`:

- `Yuka.Async.on_result async f` calls `f` with `Ok value` or
  `Error message` when the `Async` settles. When it is already settled,
  `f` runs at once.
- `Yuka.Async.status async` gives the status now.
- `Yuka.Async.watch async` gives a State that follows the status, for an
  island that renders each status. To show a value that loads, use
  [`<Yuka.Await>`](#values-that-load-await).

### Lwt and Eio

Each adapter converts between `Async` and the concurrency library of its
server.

With Dream, `Yuka_dream.to_async` turns an Lwt promise into an `Async`,
and `Yuka_dream.to_lwt` turns an `Async` into a promise. A failed promise
gives a failed `Async` with the exception text. A failed `Async` gives a
promise that fails with `Failure`:

```ocaml
let after delay compute =
  Yuka_dream.to_async (Lwt.map compute (Lwt_unix.sleep delay))
```

With tapak, you write direct-style Eio code. `Yuka_tapak.async ~sw f` runs
`f` in a new fiber and gives its result as an `Async`. An exception gives
a failed `Async`. `Yuka_tapak.switch_exn ()` gives the switch of the
current request:

```ocaml
let data =
  Yuka_tapak.async ~sw:(Yuka_tapak.switch_exn ()) (fun () ->
      Eio_unix.sleep 1.;
      "loaded after one second")
```

`Yuka_tapak.await async` waits for the `Async` in the current fiber and
gives `Ok value` or `Error message`. `Yuka_tapak.await_exn` raises
`Failure` in place of `Error`.

## Actions

An action is a function of the server that the browser calls. Declare it
in shared code. `Yuka.Action.mutation` changes data; `Yuka.Action.query`
only reads, so a server render may run it and `Yuka.Remote` may try it
again:

```ocaml
(* shared/actions.ml *)
type update_input = {
  id : string;
  status : Model.Issue.status option;
  priority : Model.Issue.priority option;
}
[@@deriving codec]

let update_issue =
  Yuka.Action.mutation ~name:"update_issue" ~input:update_input_codec
    ~output:Model.Issue.codec
```

Implement it in the server, one time at start, before the server runs:

```ocaml
(* server/handlers.ml *)
let register () =
  Yuka.Server.Action.implement Actions.update_issue
    (fun _request ({ id; status; priority } : Actions.update_input) ->
      match Store.update ~id ?status ?priority () with
      | Some issue -> Yuka.Async.return issue
      | None -> Yuka.Server.Action.reject ("No issue " ^ id))
```

`Yuka.Server.Action.reject message` refuses the input: the caller gets
`Error (Rejected message)`, and the message is for the user. Any other
failure is `Error Server`; the detail goes to the server log, not to the
browser.

Any page can call any action, and `POST /_yuka/action/NAME` runs no route
guard. An action checks permissions itself, with its request
(`Yuka.Server.Request.session`, `Yuka.Server.Request.header`).

### The request

`Yuka.Server.Request` reads the request of a loader, a guard, a handler,
an action, a form action or a live `allow`:

| Function | Gives |
| --- | --- |
| `meth`, `path` | the method; the path without the query |
| `target` | the path and the query as sent, not decoded |
| `query`, `query_param` | the decoded query pairs, in order; the first value of a name |
| `header`, `cookie` | a header (any case); a cookie value from the `cookie` header |
| `session` | the session id from the adapter |
| `body ~limit` | the body, or ``Error `Too_large`` when it is longer than `limit` bytes |
| `json ?limit codec` | the body decoded with the codec (default limit 1 MiB) |

The server reads the body from the client one time. Each later `body` or
`json` call gives the same bytes; the guards and the handler of a route
get the same request, and in an action the cycle read the body before
the action runs, so these calls read nothing more. A call with a
smaller limit than the length of the body gives ``Error `Too_large``.
After a call gave ``Error `Too_large``, each later call gives it too.

`json` keeps its errors apart: `` `Too_large ``, `` `Invalid_json message ``
(the body is not JSON) and `` `Invalid_value message `` (the codec does not
accept it).

`Yuka.Server.json codec value` answers with the value encoded as
`application/json`, and `Yuka.Server.text` with `text/plain;
charset=utf-8`. Both take `?status` (default 200) and `?headers`.

Call it from an island with `Yuka.Action.call`. The result is an
`Async` that is always `Done`, with `Ok output` or `Error error`
(`Yuka.Status.error`). `message` is a `string option Yuka.State.t`:

```ocaml
Yuka.Async.on_result
  (Yuka.Action.call Actions.update_issue
     { Actions.id = issue.id; status = Some Model.Issue.Done; priority = None })
  (function
    | Ok (Ok _issue) -> ()
    | Ok (Error error) -> Yuka.State.set message (Some (Yuka.Status.error_to_string error))
    | Error _ -> ())
```

The outer `result` is the one of `Async.on_result`: `Error` only when the
`Async` failed, which `call` never does.

In the browser, a query called while an owner is current is aborted when
that owner is disposed: when its `Yuka.Effect.after` or
`Yuka.Effect.before` runs again, or when its component goes. The `Async` of
an aborted call stays `Pending`, and a late answer is dropped. So an effect
that loads data needs no code to drop old answers: only the answer for the
latest run reaches the State. `query` and `issues` are States:

```ocaml
Yuka.Effect.after (fun () ->
    Yuka.Async.on_result (Yuka.Action.call Actions.search (Yuka.State.get query))
      (function
        | Ok (Ok found) -> Yuka.State.set issues found
        | Ok (Error _) | Error _ -> ()))
```

A mutation or a form action is not aborted that way, since an abort cannot
undo the work of the server, and a request aborted early may not reach
it. To abort any action, use `Yuka.Action.start`, which gives the `Async`
and the function that aborts the call:

```ocaml
let result, abort = Yuka.Action.start Actions.update_issue input in
(* later *)
abort ()
```

On the server, a call is never aborted, and the abort of `start` only
drops the answer. `Yuka.Remote.make` does all of this for a query and keeps
its status; use `call` in an effect when the answer goes to your own State.

## Forms

A form posts with no JavaScript, and in an island it submits through its
action with no page load. `[@@deriving form]` on a record writes the
fields: `new_issue_form`, and a polymorphic variant with one tag per
field (`` `Title `` for `title`). A field is `string`, `int`, `float`,
`bool`, an `option` or `list` of those, or a module with `t`, `of_string`
and `to_string`:

```ocaml
(* shared/actions.ml *)
module Status_field = struct
  type t = Model.Issue.status

  let of_string = Model.Issue.status_of_slug
  let to_string = Model.Issue.status_slug
end

type new_issue = { title : string; description : string; status : Status_field.t }
[@@deriving form]

let create_issue =
  Yuka.Form.action ~name:"create_issue" ~fields:new_issue_form ~output:Model.Issue.codec
```

The server implementation gives `Ok output` or a list of errors. An error
with `Some field` belongs to that field; `None` is for the whole form:

```ocaml
(* server/handlers.ml *)
Yuka.Server.Form.implement Actions.create_issue
  ~redirect:(fun (issue : Model.Issue.t) -> Links.issue issue.workspace ~id:issue.id)
  (fun _request { title; description; status } ->
    let title = String.trim title in
    if title = "" then Yuka.Async.return (Error [ (Some `Title, "Title is required") ])
    else Yuka.Async.return (Ok (Store.create ~title ~description ~status)))
```

On `Ok`, a post answers 303 to `redirect output` (default: the page URL).
On errors, the server renders the page again with status 422, the sent
values and the errors. A post runs the guards of the page it posts to,
and it can name any form action: the function checks permissions itself.

`<Yuka.Form action>` prints a `<form method="post">`. Its child is a
function of the form:

```ocaml
<Yuka.Form action=Actions.create_issue
  on_ok=(fun (issue : Model.Issue.t) -> Yuka.Browser.navigate (Links.issue issue.workspace ~id:issue.id))>
  (fun form ->
    <div>
      <label for_="title">"Title"</label>
      <input id="title" name="title" value=(Yuka.Form.value form `Title) />
      (Yuka.Form.field_error_view form `Title (fun ~id message ->
         <p id class_="error">(Yuka.text message)</p>))
      (Yuka.Form.form_errors_view form (fun message -> <p class_="error">(Yuka.text message)</p>))
      <button type_=`submit disabled=(Yuka.State.get (Yuka.Form.pending form))>"Create issue"</button>
    </div>)
</Yuka.Form>
```

- The `name` of each control is the field name of the record.
- `Yuka.Form.value form field` is the value that the user sent, after a
  failed post (422); else `""`.
- In an island, a submit decodes the fields in the browser first (an
  error shows at once, with no request), then calls the action.
  `Yuka.Form.pending form` is a read-only State, true while it waits; `disabled` above
  updates with it. On
  `Ok output`, `on_ok output` runs, or else the page follows the redirect
  of the server with a client navigation. With no redirect, the page
  calls `Yuka.Browser.refresh ()`: it loads the page again from the server
  and keeps the history entry, the scroll position and the focus.
- Two forms of one action on a page need different `key`s:
  `<Yuka.Form action key="top">`.

### Form errors

`Yuka.Form.field_error_view` gives the view of a field error an `id`. Put
it on the element of the error, as above.

While the field has an error, `Yuka.Form` sets `aria-invalid="true"` on
each `input`, `select` and `textarea` of the form with that `name`, and
adds the `id` to its `aria-describedby`, after the ids that the field
already has. When the error goes, it removes both. A screen reader then
reads the error with the field. An `aria-invalid` that you set on a field
with no Yuka error stays.

After a submit in the browser that ends with field errors, the focus goes
to the first field with an error. On a failed post with no JavaScript
(422), the server prints these attributes, and `autofocus` on the first
field with an error, so the page opens on it.

`Yuka.Form.form_errors_view` shows the errors for the whole form (a
refused request, an error from the server) in a
`<div role="alert" tabindex="-1">`, so a screen reader reads them when
they show. When a submit in the browser ends with errors for the whole
form and no field takes the focus, the focus goes to that `div`. On a
failed post (422) with no field errors, the server prints `autofocus` on
it.

The `id` is made from the action name, the `key` of the form and the
field name. A development build shows an error in the browser console
when two forms on a page have the same action and key.

To show the errors another way, read `Yuka.Form.errors form`, a read-only
State, with `Yuka.State.get` in markup, and give its value to
`Yuka.Form.field_error` (the first error of a field) or
`Yuka.Form.form_errors` (the errors for the whole form):

```ocaml
<p class_="error">
  (Yuka.text (Option.value ~default:"" (Yuka.Form.field_error (Yuka.State.get (Yuka.Form.errors form)) `Title)))
</p>
```

## Remote data

`Yuka.Remote.make` runs a query and keeps its status. Call it in a
component body. It runs again when a State that its input function reads
changes:

```ocaml
(* shared/user_popup.mlx *)
type input = { workspace : Model.Workspace.t; user : string } [@@deriving codec]
type stats = { open_ : int; in_progress : int; done_ : int } [@@deriving codec]

let stats = Yuka.Action.query ~name:"user_stats" ~input:input_codec ~output:stats_codec

module Card = struct
  let make ~workspace ~(user : Model.User.t) () =
    let remote = Yuka.Remote.make stats (fun () -> { workspace; user = user.id }) in
    <Yuka.Show status=(fun () -> Yuka.State.get (Yuka.Remote.state remote))
      loading=(<p>"Loading..."</p>)
      failed=(fun _ -> <p>"Could not load the numbers."</p>)>
      (fun (stats : stats) -> <p>(Yuka.text (Printf.sprintf "%d open" stats.open_))</p>)
    </Yuka.Show>
end
```

The server implements the query as any action:

```ocaml
Yuka.Server.Action.implement User_popup.stats (fun _request { workspace; user } ->
    Yuka.Async.return (Store.user_stats workspace user))
```

- In a server render, the query runs once. Inside an island, the answer
  is written in the page, and the browser reads it with no request.
  After a client navigation, a use in a kept layout reads the answer of
  its key that the new page brings, so a layout island and a page island
  with the same query show the same data.
- A `Network` or `Server` error is tried again two times, after 500 ms
  and 1500 ms (`?retry`). `?enabled` stops the query while it is false.
- `Yuka.Remote.refetch remote` sends it again, for every use with the
  same input. `Yuka.Remote.invalidate query` sends again every use of the
  query on the page, for example after an action changed the data. The
  uses with the same input share one request: a use that starts waits on
  the one in flight, and a refetch or an invalidate replaces it, so no
  answer from before them is shown.
- `Yuka.Remote.optimistic` shows a change at once and removes it when
  the action fails.

## Show a status

`Yuka.Remote.state` and `Yuka.Live.state` give a read-only State of a
`Yuka.Status.t`, with the pending optimistic changes applied; read it with
`Yuka.State.get`. A status is
`Idle`, `Loading (Some last)`, `Ready { data; stale }` or
`Failed { error; last }`. `<Yuka.Show>` shows it, as in the sample above:

- `Ready` and `Loading (Some data)` show the children with the data, so
  the data stays on the page while it loads again.
- `Idle` and `Loading None` show `loading`.
- `Failed` shows `failed error` (default: nothing).

`Yuka.Status.data status` gives the data as an option, for a memo.

## Live data

Live data is server state that the server pushes to the page when it
changes, over one WebSocket for the page. A topic is a kind of live
state; it has one state per key. Declare it in shared code:

```ocaml
(* shared/topics.ml *)
let issue = Yuka.Topic.declare ~name:"issue" ~key:Yuka.Codec.string ~state:Model.Issue.codec
```

The server gives a loader: the full state of a key. `?allow` decides who
may read a key; the loader gets no request, because every subscriber of
a key shares its state:

```ocaml
(* server/handlers.ml *)
Yuka.Server.Live.implement Topics.issue (fun id ->
    match Store.find id with
    | Some issue -> Yuka.Async.return issue
    | None -> Yuka.Server.Action.reject ("No issue " ^ id))
```

An island subscribes with `Yuka.Live.make`:

```ocaml
(* shared/issue_props.mlx *)
let[@client] make ~(issue : Model.Issue.t) () =
  let live = Yuka.Live.make Topics.issue (fun () -> issue.id) in
  let current =
    Yuka.State.memo (fun () -> Option.value (Yuka.Status.data (Yuka.State.get (Yuka.Live.state live))) ~default:issue)
  in
  <p>(Yuka.text (Model.Issue.status_label (Yuka.State.get current).status))</p>
```

When an action changes the data, it publishes the new state:

```ocaml
Yuka.Server.Live.publish Topics.issue issue.id issue
```

Use `Yuka.Server.Live.changed topic key` when the action does not have
the new state: the server runs the loader again. `Yuka.Live.optimistic`
shows a change at once, as `Remote.optimistic` does, and keeps it until
the published state arrives.

The server sends a subscriber the changes from the state it has (a patch)
when the patch is short, else the full state. When the socket closes, the
status is `Ready { stale = true }` while the browser connects again; after
the reconnect, the page gets the full state again. In a server render,
`Live.make` runs `allow` and reads the state (the loader runs when the node
has none), and an island starts from that state with no wait.

`Live.make` needs a session: with Dream, `Dream.cookie_sessions` and
`Dream.set_secret`, with a secret that is the same on every server and
after a restart. A page that uses it cannot be prerendered, and its route
must not use a shared cache.

### Nodes and the bus

A node is the live state of one server process: its sockets and
subscriptions. `Yuka.Server.Live.node` makes one and sets its limits:
`max_sockets` (default 10,000) and `max_sockets_per_session` (default 16)
open sockets, and `max_kept_states` (default 10,000) and
`max_kept_states_per_session` (default 16) states kept from server
renders.

A publish reaches the sockets of its node only. With more than one server
process, join each one to a bus with `Yuka.Server.Live.use_bus`: a
publish then tells the other nodes, which run the loader again for their
own subscribers. Each node must read the same storage. The
`yuka-live-pg` package gives a bus over Postgres `LISTEN`/`NOTIFY`
(`Yuka_live_pg.bus`); [Getting started](getting-started.md#live-data-on-more-than-one-server)
shows how to wire it.

## Values that load: Await

`<Yuka.Await>` shows a `Yuka.Async.t`. The server waits a short time for
the value before it sends the page. A value that is ready by then is in
the page; for the others the page has `loading`, and the server streams
each value in the same response when it is ready:

```ocaml
(* shared/related.mlx *)
let[@client] make ~(related : Model.Issue.t list Yuka.Async.t) () =
  <Yuka.Await async=related
    loading=(<p>"Loading..."</p>)
    failed=(fun message -> <p class_="error">(Yuka.text ("Could not load: " ^ message))</p>)>
    (fun issues -> <p>(Yuka.int (List.length issues))</p>)
  </Yuka.Await>
```

`<Yuka.Await>` works on the server page and in an island. An `Async`
prop of an island streams the same way (see [Islands](islands.md#props)).

`blocking` says how long the server waits for the value, on a first load
and on a client navigation:

- `` `Yes ``: until the value settles, or the request timeout ends. Use
  it for the main content of the page, such as the title of an issue.
- `` `No ``: the server does not wait. Use it for content that can come
  later, such as a slow sidebar.
- `` `Timeout s `` (the default is `` `Timeout 0.1 ``): up to `s` seconds.

```ocaml
<Yuka.Await async=issue blocking=`Yes loading=(<Skeleton />)>
  (fun issue -> <h1>(Yuka.text issue.title)</h1>)
</Yuka.Await>
```

The server sends the page when each pending value is settled or past its
own limit, so the page waits at most the largest limit among the values
still pending. A value that settles in that time is in the page, whatever
its own limit: it has no `loading` flash and no fill script. The wait
delays the first byte of the page: a page with a slow value sends its
first byte up to that largest limit later.

A page whose `Cache-Control` is shared (`public` or `s-maxage`) does not
stream: the server sends it when every `Await` has settled, whatever
`blocking` says.
In a server render, `message` is the message of a
`Yuka.Server.Action.reject`, else `"server error"`, so the HTML never has
the detail of a failure.

When the connection breaks before a pending value comes, the `Await`
shows `failed "broken"`, on a first load and on a client navigation.
The server sends that view with the page, so keep `failed` small. The
values that came stay. See [Router](router.md) for `Yuka.Browser.stream`.

## Errors: Catch

`<Yuka.Catch>` is an error boundary. An exception that its children raise
while they render, in an effect, or in an event handler, shows the
fallback in their place:

```ocaml
<Yuka.Catch fallback=(fun ~error:_ ~reset ->
    <div>
      <p class_="error">"The properties could not be shown."</p>
      <button on_click=(fun _ -> reset ())>"Try again"</button>
    </div>)>
  <div class_="props">(properties ())</div>
</Yuka.Catch>
```

`reset ()` renders the children again from their first state. A failed
`Async` or a `Failed` status is a value, not an exception: show it with
`Await` or `Show`. On the server, `error` is `"server error"` and the
exception goes to the server log.

To show a list that changes, with rows that keep their DOM nodes, use
`Yuka.each`; see [State](state.md#keyed-lists).
