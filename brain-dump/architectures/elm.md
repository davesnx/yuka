# Elm 0.19.1: architecture and how it solves P1-P20

Marks: "(src)" = read in a primary source this session. "(memory)" = written from memory, not checked. Unmarked sentences are backed by the sources listed in `## Sources`. The chat-room code was not compiled (no Elm compiler in the sandbox).

## Model

A program is four values and a runtime.

```elm
type alias Program flags model msg = -- schematic
    { init          : flags -> ( model, Cmd msg )
    , update        : msg -> model -> ( model, Cmd msg )
    , view          : model -> Html msg
    , subscriptions : model -> Sub msg
    }
```

- `Model` is one immutable value. It holds all state of the program.
- `Msg` is a custom type. Every event (click, HTTP result, timer tick, port message) is a `Msg` value.
- `update` is the only place that produces a new `Model`. It also returns a `Cmd`.
- `view` is a pure function of `Model`. Event attributes (`onClick Save`) carry `Msg` values, not callbacks that act.
- `subscriptions` is a pure function of `Model`. It declares which outside events the program wants now.
- `Cmd msg` and `Sub msg` are values, not actions. The docs: "Effects are managed: they are treated as data, and the runtime can optimize them before performing them." (src: Platform.Cmd)
- `Cmd.batch`, `Cmd.none`, `Cmd.map` combine and re-tag commands. `batch` gives "no ordering guarantees about the results". (src)
- `Cmd.map` and `Sub.map` are, in the docs' words, "very rarely useful in well-structured Elm code". (src) (`Html.map` is the one used in practice for nested modules; see P1.)

Runtime (src: elm/core `Elm/Kernel/Platform.js`, `Scheduler.js`; elm/browser `Elm/Kernel/Browser.js`):

1. `init` runs once. Its model is kept. Its `Cmd` and `subscriptions model` are queued as effects.
2. For each `Msg`, `sendToApp` runs `update msg model`, stores the new model, hands the model to the stepper (the view), and queues the returned `Cmd` and `subscriptions newModel`.
3. Commands and subscriptions are trees ("bags"). The runtime walks them, applies the `map` taggers, and sends each effect to the effect manager that owns it.
4. An effect manager is an Elm module with its own state and a process. Its `onEffects` receives the full current list of commands and subscriptions each time. `onSelfMsg` handles its own internal events. Only `elm/*` packages can define managers (memory: 0.19 blocks third-party effect managers). HTTP, Time, Browser events, Dom focus, Random are built this way.
5. Processes are light-weight and run on a cooperative scheduler: one global queue, one step at a time, no re-entrancy. `Process.kill` stops a process; for an in-flight task it calls the task's kill function (src: Scheduler.js).
6. View drawing is separate from `update`. The first draw is synchronous. Later draws happen at most once per animation frame, unless the update is synchronous (src: Browser.js `_Browser_makeAnimator`).

Ports (src: guide "Ports", Platform.js):

- `port sendOut : Value -> Cmd msg` and `port comeIn : (Value -> msg) -> Sub msg`. The module must start with `port module`. Ports work only in applications, not packages. (src)
- JS side: `app.ports.sendOut.subscribe(fn)` and `app.ports.comeIn.send(value)`.
- A value that fails to decode on an incoming port makes the runtime crash (src: Platform.js calls `Debug_crash` on decode failure).
- The guide says: "Ports are about creating strong boundaries!" and recommends sending `Json.Encode.Value`. (src)

## Problems

### P1 Unit of composition

Elm has no component. The unit is a function plus a type. The official guide says: "Actively trying to make components is a recipe for disaster in Elm." Reason: "components = local state + methods", and Elm has no objects. (src: guide, Structure)

- Views are plain functions: `viewSidebar : Sidebar -> Html Msg`. No own `update` is needed. (src)
- Guide advice: build modules around one central type. Do not plan for reuse. Extract after you see the same code twice. Do not split into `Model`/`Update`/`View` modules. (src)
- When a part needs its own state and messages (nested TEA), the parent wraps them. Real-world example, elm-spa-example `Main.elm` (src):

```elm
type Model = Home Home.Model | Article Article.Model | ...
type Msg   = GotHomeMsg Home.Msg | GotArticleMsg Article.Msg | ...
Home.init session |> updateWith Home GotHomeMsg model   -- wraps model and Cmd.map
```

- Parent to child: pass values as arguments, or call the child's `update` directly. Child to parent: the child's `update` returns an extra value (an "out message") or the parent reads the child's `Msg` first. Both are conventions, not features (memory: "OutMsg" pattern; elm-spa-example uses `Session` passed down and read back).
- Cost: the wrapping code at each level (see P19). A message for a page the user has left falls into a catch-all branch and is ignored (src: elm-spa-example).

### P2 Local state

Elm has no local state. All state is in the one `Model`. "Local" state is a field or sub-record that the parent owns.

- Created in `init` or in the branch of `update` that creates it (elm-spa-example: `changeRouteTo` builds the page model, src).
- Identity is the position in the `Model` value: a record field, a variant (`Home m`), or a key in a `Dict` for many items (memory: `Dict Id ItemModel` is the usual form).
- Switching a variant (page) drops the old state. Nothing keeps it unless the parent stores it elsewhere.
- Cost: state for a small widget (open/closed dropdown) is visible and must be threaded through the parent's model and messages. The benefit: all state is in one inspectable value (see P17).

### P3 Props and inputs

Inputs are values: arguments to `view` functions. There are no reactive inputs.

- A child view is called again on every parent draw with the current values. A change reaches the child because the function is called again. (src: runtime draws the full view; see P5)
- If a child has its own `Model`, the parent passes new inputs by calling `Child.update` with a message or by editing the child's model in its own `update` (memory: common practice).
- Nothing tells a child "prop X changed". See P8.

### P4 Derived state and memoization

Elm has no memo for derived state. Two options:

- Compute in `view` each time (cheap values).
- Store it in the `Model` and recompute in `update` where the source changes. The programmer must keep both in step. A custom type that exposes only a smart constructor helps (memory: common advice).

`Html.Lazy.lazy f a b` memoizes a view fragment (src: Lazy.elm docs; VirtualDom.js):

- Each argument is compared with JS `===`. If all match, the old subtree is reused. "Since all Elm functions are pure we have a guarantee that the same input will always result in the same output."
- Only the last result is kept (src: jfmengels, via `elm.md`). A -> B -> A recomputes.
- Equal data with a new reference misses. A record rebuilt each time defeats it. Max 8 arguments (`lazy8`). (src)
- So equality is decided by reference. The author cannot supply an `equal`.
- The docs advise benchmarking: it is "a really cheap test" but helps only sometimes. (src)

### P5 Update granularity

After a `Msg`, `update` runs, then the whole `view model` function runs, then the new virtual tree is diffed against the old one, then patches go to the DOM (src: Browser.js: `diff(currNode, nextNode)`, `applyPatches`). There is no dependency tracking.

- `lazy` skips both `f` and the diff for a subtree when its arguments are `===` (src). `f` runs only during diff or render, not while building the tree.
- Putting `lazy` at the root gives nearly "skip view when model is unchanged". A nested update such as `{ model | x = Page.update m model.x }` always builds a new record, so a root `lazy` misses. Move `lazy` down to sub-views taking sub-models. (src: jfmengels "make your roots lazy", via `elm.md`)
- Events: handlers are compared by their decoder structure; if the tag is the same, the DOM listener stays and only the stored handler is replaced (src: VirtualDom.js `_VirtualDom_equalEvents`, `applyEvents`).

### P6 One-shot effects

Return a `Cmd` from `update`. The result returns as a `Msg`.

```elm
Clicked -> ( { model | status = Loading }, Http.get { url = "/x", expect = Http.expectJson GotX decoder } )
```

- `Http.Error` is `BadUrl | Timeout | NetworkError | BadStatus Int | BadBody String`. `expectJson` gives `Result Http.Error a`, so the compiler forces both cases to be handled. (src: elm/http; guide "HTTP")
- `Task` is a description of work. It runs only through `Task.perform` (cannot fail) or `Task.attempt` (gives a `Result`). `Task.sequence` runs tasks one by one, and the whole fails if one fails. (src: Task.elm)
- Cost: a handler cannot read the result inline. The result arrives as a separate `Msg`, and the programmer must carry any needed context in that message (see P18).

### P7 Long-lived effects

Two mechanisms.

1. `subscriptions : Model -> Sub Msg`. The runtime calls it after every update. The effect manager compares the new list with what is running. Example, `Time.every` (src: Time.elm): one timer process per interval; new interval spawns a timer; an interval no longer listed has its process killed; same interval keeps its timer.
   The lifetime is "while the model says so". Start and stop are decided by the model, not by a call.
2. Ports for anything without a package (WebSocket, localStorage). The port only passes data. The socket lives in JavaScript, so Elm cannot see or control its lifetime except by sending commands (`openRoom`, `closeRoom`). See `## Chat room`.

There is no `WebSocket` package in 0.19 (the task brief states this; the old `elm-lang/websocket` is 0.18, memory).

### P8 "When X changes, do Y"

Elm has no watcher on state. The programmer puts the reaction in the `update` branch that changes X.

```elm
SelectRoom room -> enter room { model | room = room }   -- enter returns the Cmd for the new room
```

- Cost: every code path that can change X must call the reaction. One helper function (`enter`) is the usual way to keep it in one place (memory). Nothing checks that a path forgot it.
- For effects that should follow state, use `subscriptions model` (P7): the reaction is derived from the model, so it cannot be forgotten.
- No "previous value" is available in `view`. In `update`, the old model is an argument, so it can be compared with the new one (`if old.room /= new.room`).

### P9 Cleanup and cancellation

- Subscriptions are cleaned up by the runtime when they disappear from `subscriptions model` (P7). No cleanup code is written. (src: Time.elm)
- HTTP: give `Http.request` a `tracker : Maybe String`, then `Http.cancel "tracker"`. The docs say "Try to cancel", so it is best-effort. (src: elm/http)
- `Process.kill` stops a process, including an in-flight task. `Process.spawn` gives a process id that the programmer must keep in the model. (src: Process.elm)
- Even a cancelled or slow request can arrive late. The common guard is to put the key (room, query) in the `Msg` and ignore the result when it no longer matches the model (see P18).
- Ports: JS must close its own resources (memory/see chat code).

### P10 Async data, loading and error states

No Suspense. The model holds the state as a custom type. Guide example (src: "HTTP"):

```elm
type Model = Failure | Loading | Success String
```

- The view matches on it, so each state is rendered by construction. The compiler flags a missing case.
- The package `krisajenkins/remotedata` packages this as `NotAsked | Loading | Failure e | Success a` (memory).
- Dependencies between loads (second request needs the first) are chained by hand: a new `Cmd` from the `update` branch for the first result, or `Task.andThen`. Parallel loads: `Cmd.batch`, one `Msg` each, and the model tracks each state separately. There is no boundary that waits for a group of children.

### P11 Keyed lists

`Html.Keyed.node` / `Keyed.ul` take `List ( String, Html msg )`. Docs: "every child is paired with a string identifier"; use it "when you have a list of nodes that is changing: adding nodes, removing nodes, etc." (src: Keyed.elm)

- The diff matches children by key. It looks ahead one position on each side for insert, remove, and swap, and converts a remove plus a later insert of the same key into a move. Duplicate keys get a suffix instead of failing. (src: VirtualDom.js `diffKeyedKids`)
- Keys keep DOM identity (focus, scroll position, input value inside the item, CSS transitions). They do not carry Elm state, since there is none.
- Without keys, children are diffed by position.
- Many items with own state: a `Dict Key ItemModel` in the model (memory).

### P12 Batching and scheduling of updates

- Each `Msg` runs `update` synchronously, one at a time, in order. The model is never half-updated.
- Draws are batched: async updates within one frame collapse into one `requestAnimationFrame` draw. A synchronous update draws immediately. (src: `_Browser_makeAnimator`)
- Effect batches are queued so that a synchronous command (for example `Time.now`) that causes a nested `update` does not reorder subscriptions. (src: `_Platform_enqueueEffects` comments)
- Command results have no ordering guarantee relative to each other. (src)
- No priorities. All messages are equal.

### P13 Concurrency: transitions, deferred values, optimistic updates

Elm deliberately has none of the first two. The `Process` docs separate "concurrency" (interleaving) from parallelism and say the long-term plan "will be rolling out" gradually. (src: Process.elm) Rendering is not interruptible.

- Transitions: not available. The programmer keeps the old data in the model and shows a spinner field. (memory)
- Deferred values: not available.
- Optimistic updates: by hand. Add the item to a `pending` list with a client-made id, send, then remove it when the server echoes that id (or on failure). See `## Chat room`.
- Elm programs are single-threaded. Web Workers are used through ports (memory).

### P14 Error handling

- Expected failures are values: `Result`, `Maybe`, `Http.Error`. The compiler enforces handling.
- Elm 0.19 has no exceptions in user code and no error boundary. The language has no `try`. (memory)
- Failures at the JS boundary can crash: bad data on an incoming port (src: Platform.js), a JS exception in a port subscriber (memory), an unknown flag shape (flags are decoded; failure throws at `init`, src: Platform.js).
- There is no way to catch and render a fallback for a subtree. Isolation is done by decoding at the boundary into a `Result`. (memory)

### P15 Server rendering and hydration

Elm has no server renderer built in. `elm/html` produces a virtual tree for the browser only. (memory: no `renderToString` in elm/html)

- `Browser.element` and `Browser.document` do not create the DOM from nothing: `_Browser_element` calls `_VirtualDom_virtualize(domNode)` on the mount node and patches in place (src: Browser.js). So server markup placed inside the node is converted to a virtual tree and then diffed against the first real `view`. (Event listeners attach through that first diff; this is an inference from the code, not stated in a source.)
- `elm-pages` (Dillon Kearns) adds pre-rendering at build time and server-rendered routes. Its README says: "You can mix and match server-rendered and pre-rendered routes in your app." (src: elm-pages README) How its hydration works was not read (its docs pages returned 404). It runs Elm code in Node to produce HTML (memory) and boots the browser app with the same model (memory).
- Other approaches (memory): `elm-explorations/markup` or a hand-written `Html` to `String` function, run in a JS runtime.
- The data that the browser needs at start comes through `flags`. The server and the browser must produce the same initial `Model` or the first diff changes the page.

### P16 Testing

- `elm-explorations/test` gives unit tests and fuzz tests (100 runs by default); a runner such as `elm-test` executes them. `Test.Html.Query`, `.Selector`, `.Event` test views. (src: package README)
- `update` is a pure function, so it is tested with plain values. A `Cmd` is opaque: it cannot be inspected or compared (memory). That is why `elm-program-test` exists: it runs a whole program with simulated user actions and effects, and asserts on the view (src: README; how effect simulation works was not described in the page I read, memory: uses `SimulatedEffect`).
- The test package README states: "There is currently no Elm solution for integration or end-to-end testing", and recommends tools such as Cypress. (src)
- Ports, and the JS side of any socket, need separate JS tests.

### P17 Debugging

- Build with `elm make --debug` (src: elm-spa-example README). The debugger records every `Msg` with the model before it. (src: Debugger/Main.elm)
- Time travel: jump to any index; the model at that index is rebuilt by replaying messages through `update`. Commands from past messages are not re-run. (src)
- Export: downloads JSON with `metadata` and `history`. Import: replays the history through a pure `update` (`Tuple.first (update msg model)`) and shows the result. A bug report can therefore be a file. (src) Decode fails if the `Msg` type changed (memory).
- Replay is deterministic because `update` and `view` are pure and every outside input is a `Msg`. Effects are not replayed, but their results are in the history as messages.
- "Why did this render": the view reruns after every message (P5). The history shows which message came before. `lazy` misses are not reported (memory).
- `Debug.log` prints values. It is rejected in `--optimize` builds (memory).

### P18 Stale reads and common footguns

- No stale closures: handlers hold `Msg` values, and `update` gets the current model. This removes the React stale-closure class of bugs.
- Late results: a response for room A can arrive after the user moved to room B. Elm does not drop it. The guard is the programmer's (key in the `Msg`, compare in `update`). `Http.cancel` is best-effort. (src)
- Messages for a page that no longer exists must be ignored explicitly (src: elm-spa-example catch-all).
- `Cmd.batch` order is not guaranteed. (src)
- `lazy` with a freshly built record or `Html.map` closure always misses (src: jfmengels via `elm.md`).
- Duplicate keys in a keyed node are silently renamed. (src)
- Port JSON shape errors crash at runtime, not at compile time. "The compiler does not know what goes on in JavaScript." (src: guide)
- `==` on functions throws at runtime in Elm; `lazy` uses JS `===`, so structural equality and lazy equality differ. (memory)

### P19 Boilerplate and learning curve

- Small apps: little code. The language is small, there is one architecture, and the compiler messages are guided. (memory)
- Cost grows with nesting: each child needs a `Msg` variant, a `Model` field or variant, `Cmd.map`, `Html.map` and a call to the child's `update`. elm-spa-example hides this behind one `updateWith` helper. (src)
- The guide's answer is to nest less: keep a flat model and extract view functions. (src)
- Effects without a package need ports and JavaScript.
- Every external value needs a `Json.Decode` decoder. (memory)

### P20 Typing guarantees

- `Msg` is a closed custom type: `case` must cover all variants (exhaustiveness is enforced).
- `Html msg`, `Cmd msg`, `Sub msg` carry the message type, so an event in a child cannot produce a message of the wrong type. Re-tagging is explicit with `Html.map`.
- Custom types model states that cannot co-exist (`Loading | Failure | Success`). (src: guide)
- No runtime exceptions from the language in normal code (no null, no `undefined`). (memory)
- Boundaries (ports, flags, HTTP bodies) are typed in Elm but unchecked on the JS side. Decoders turn failure into `Result`, except incoming ports and flags, which crash. (src: Platform.js)
- There are no type classes or higher-kinded types, so abstractions over `Cmd`/`Html` are plain functions. (memory)

## Chat room

One module, `port module Main`. The "parent" (room picker) and the chat share one `Model`. With nested TEA, the chat would be `Page.Chat` with `init room`, and the parent would wrap it as in P1.

```elm
port module Main exposing (main)

import Browser
import Html exposing (..)
import Html.Attributes exposing (disabled, style, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed as Keyed
import Http
import Json.Decode as Decode
import Json.Encode as Encode

port joinRoom : String -> Cmd msg
port sendMessage : Encode.Value -> Cmd msg
port received : (Encode.Value -> msg) -> Sub msg

type alias Message = { clientId : String, text : String }
type History = Loading | Failed Http.Error | Loaded

type alias Model =
    { room : String, history : History, messages : List Message
    , pending : List Message, draft : String, counter : Int, session : String }

type Msg
    = SelectRoom String | GotHistory String (Result Http.Error (List Message))
    | Received Encode.Value | Draft String | Send

main : Program String Model Msg
main = Browser.element { init = init, update = update, view = view, subscriptions = \_ -> received Received }

init : String -> ( Model, Cmd Msg )
init session = enter "general" { room = "", history = Loading, messages = [], pending = [], draft = "", counter = 0, session = session }

enter : String -> Model -> ( Model, Cmd Msg )
enter room model =
    ( { model | room = room, history = Loading, messages = [], pending = [] }
    , Cmd.batch [ Http.cancel "history", fetchHistory room, joinRoom room ] )

fetchHistory : String -> Cmd Msg
fetchHistory room =
    Http.request
        { method = "GET", headers = [], url = "/api/rooms/" ++ room ++ "/messages", body = Http.emptyBody
        , expect = Http.expectJson (GotHistory room) (Decode.list messageDecoder), timeout = Nothing, tracker = Just "history" }

messageDecoder : Decode.Decoder Message
messageDecoder = Decode.map2 Message (Decode.field "clientId" Decode.string) (Decode.field "text" Decode.string)

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SelectRoom room -> if room == model.room then ( model, Cmd.none ) else enter room model
        GotHistory room result ->
            if room /= model.room then ( model, Cmd.none )
            else case result of
                Ok ms -> ( { model | history = Loaded, messages = merge ms model.messages }, Cmd.none )
                Err e -> ( { model | history = Failed e }, Cmd.none )
        Received value ->
            case Decode.decodeValue (Decode.map2 Tuple.pair (Decode.field "room" Decode.string) messageDecoder) value of
                Ok ( room, m ) ->
                    if room /= model.room then ( model, Cmd.none )
                    else ( { model | messages = merge model.messages [ m ], pending = List.filter (\p -> p.clientId /= m.clientId) model.pending }, Cmd.none )
                Err _ -> ( model, Cmd.none )
        Draft s -> ( { model | draft = s }, Cmd.none )
        Send ->
            let m = { clientId = model.session ++ "-" ++ String.fromInt model.counter, text = model.draft }
            in ( { model | pending = model.pending ++ [ m ], draft = "", counter = model.counter + 1 }
               , sendMessage (Encode.object [ ( "room", Encode.string model.room ), ( "clientId", Encode.string m.clientId ), ( "text", Encode.string m.text ) ]) )

merge : List Message -> List Message -> List Message
merge a b = a ++ List.filter (\m -> not (List.any (\x -> x.clientId == m.clientId) a)) b

view : Model -> Html Msg
view model =
    div []
        [ select [ onInput SelectRoom, value model.room ] (List.map (\r -> option [ value r ] [ text r ]) [ "general", "ocaml", "elm" ])
        , case model.history of
            Loading -> p [] [ text "Loading..." ]
            Failed _ -> p [] [ text "Could not load history." ]
            Loaded -> text ""
        , Keyed.ul [] (List.map (viewMessage False) model.messages ++ List.map (viewMessage True) model.pending)
        , input [ value model.draft, onInput Draft ] []
        , button [ onClick Send, disabled (model.draft == "") ] [ text "Send" ]
        ]

viewMessage : Bool -> Message -> ( String, Html Msg )
viewMessage isPending m =
    ( m.clientId, li [ style "opacity" (if isPending then "0.5" else "1") ] [ text m.text ] )
```

JavaScript side (`Elm.Main.init({ node, flags: sessionId })` then):

```js
let ws = null;
app.ports.joinRoom.subscribe(room => {
  if (ws) ws.close();
  ws = new WebSocket("wss://example.test/rooms/" + room);
  ws.onmessage = e => app.ports.received.send({ room, ...JSON.parse(e.data) });
});
app.ports.sendMessage.subscribe(m => ws.send(JSON.stringify(m)));
```

Server rendering: Elm has no built-in renderer. With `elm-pages`, the room page can be pre-rendered or server-rendered with the history fetched on the server and passed to the browser app. The browser then runs the same `init`, and `Browser` virtualizes the existing DOM and patches it (P15). The socket is opened only in the browser, after `init`, through the `joinRoom` command.

P-items exercised: P1 (parent and chat in one model), P2 (all state in `Model`), P6 (HTTP Cmd), P7 (socket through ports, lifetime in JS), P8 (`enter` helper on room change), P9 (`Http.cancel`, `ws.close()`), P10 (`History` type), P11 (Keyed), P13 (optimistic `pending`), P14 (decode into `Result`; bad port data is dropped by decoding to `Value` first), P18 (room tag on late results), P20 (`Msg`, `Value` boundary).

Awkward points:

- The socket lifetime is not tied to the model. Elm only sends `joinRoom`; JS owns the socket. A `Sub` cannot express it. If `joinRoom` is forgotten in one code path, the room and the socket diverge. The `enter` helper is the only protection.
- Late data guards are manual: room tag in `GotHistory` and in the socket payload. `Http.cancel` is best-effort.
- `ws.send` throws if the socket is still connecting, and nothing reports a send failure back. A pending message can stay pending forever. A real version needs buffering in JS, an ack timeout, and a `Failed` state per pending item.
- The client id counter needs a session id from `flags` so ids do not collide after a reload.
- Messages that arrive on the socket before the history loads are merged by `clientId`. This merge is written by hand.
- Incoming port values are decoded in `update`. Using `Encode.Value` avoids the runtime crash that a mistyped port gives.
- Untested: this code was not compiled (no Elm compiler in this sandbox).

## Sources

- https://guide.elm-lang.org/interop/ports.html : read.
- https://guide.elm-lang.org/effects/http.html : read.
- https://guide.elm-lang.org/webapps/structure.html : read.
- https://raw.githubusercontent.com/elm/core/1.0.5/src/Platform/Cmd.elm : read.
- https://raw.githubusercontent.com/elm/core/1.0.5/src/Platform/Sub.elm : read.
- https://raw.githubusercontent.com/elm/core/1.0.5/src/Elm/Kernel/Scheduler.js : read.
- https://raw.githubusercontent.com/elm/core/1.0.5/src/Elm/Kernel/Platform.js : read.
- https://raw.githubusercontent.com/elm/core/1.0.5/src/Process.elm : read (summary of the fetched tool output).
- https://raw.githubusercontent.com/elm/core/1.0.5/src/Task.elm : read.
- https://raw.githubusercontent.com/elm/time/1.0.0/src/Time.elm : read.
- https://raw.githubusercontent.com/elm/html/1.0.0/src/Html/Keyed.elm : read.
- https://raw.githubusercontent.com/elm/html/1.0.0/src/Html/Lazy.elm : read.
- https://raw.githubusercontent.com/elm/http/2.0.0/src/Http.elm : read.
- https://raw.githubusercontent.com/elm/browser/1.0.2/src/Browser.elm : read. It does not describe animation-frame batching.
- https://raw.githubusercontent.com/elm/browser/1.0.2/src/Elm/Kernel/Browser.js : read.
- https://raw.githubusercontent.com/elm/browser/1.0.2/src/Debugger/Main.elm : read. How `History` stores snapshots was not shown.
- https://raw.githubusercontent.com/elm/virtual-dom/1.0.3/src/Elm/Kernel/VirtualDom.js : read (lazy, keyed diff, events). The stepper is in Browser.js, not here.
- https://raw.githubusercontent.com/rtfeldman/elm-spa-example/master/src/Main.elm : read.
- https://github.com/rtfeldman/elm-spa-example : read (README only: build notes, `--debug`).
- https://raw.githubusercontent.com/elm-explorations/test/2.2.0/README.md : read.
- https://raw.githubusercontent.com/avh4/elm-program-test/master/README.md : read. It does not explain how effects are simulated.
- https://raw.githubusercontent.com/dillonkearns/elm-pages/master/README.md : read. It does not explain hydration.
- https://package.elm-lang.org/packages/avh4/elm-program-test/latest/ : failed (HTML shell only; the page is an Elm app).
- https://elm-pages.com/docs/how-elm-pages-works/ : failed (HTTP 404).
- https://elm-pages.com/docs/pre-render/ : failed (HTTP 404).
- https://elm-lang.org/news/the-perfect-bug-report : failed (no article text returned).
- /home/me/workplace/davesnx/yuka/brain-dump/elm.md : read (background). Its jfmengels claims were not re-fetched here; I marked them "via `elm.md`". Its Html.Lazy points agree with the VirtualDom.js source I read.
- Not fetched: Elm compiler source, `elm/json`, `elm/random`, `elm/url`, the Elm discourse and any 0.19 effect manager restriction text. Claims on those are marked (memory).
- Fetch tool note: pages were summarised by a small model, so quotes marked (src) are as that tool returned them, not read line by line by me.
