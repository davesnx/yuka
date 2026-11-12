open Types

type 'kind element = node
type 'kind attribute = attr

let text s = Text s
let int n = Text (string_of_int n)
let float f =
  Text
    (if f <> f then "NaN"
     else if f = infinity then "Infinity"
     else if f = neg_infinity then "-Infinity"
     else Json.float_repr f)
let empty = Fragment []
let fragment children = Fragment children
let element tag attrs children =
  Client.use_element ();
  Element { tag; attrs; children }

let log = Types.log

let valid name =
  if Web.in_browser && not (Url.valid_name name) then invalid_arg ("Yuka: refused attribute name " ^ name)

let url_attr _tag name value =
  valid name;
  Static (name, value)
let attr name value = url_attr "" name value

let attr_unchecked name value =
  Web.refuse_url_name name;
  Static (name, value)
let hole f = Hole f
let slot s =
  Client.use_slot ();
  Slot s

module Slot = struct
  let make content = { content = Some content; dom = ref [] }
end

type stylesheet = string

let stylesheet href = href

let use_css href body =
  if !Base.server_rendering then
    Fragment
      [ element "link" [ Static ("rel", "stylesheet"); Static ("href", href); Static ("data-yuka-css", "") ] [];
        body ]
  else begin
    if Web.in_browser then Web.add_stylesheet href;
    body
  end

let url_hole_attr _tag name f =
  valid name;
  Dynamic (name, f)

let hole_attr name f = url_hole_attr "" name f
let hole_attr_unchecked name f =
  Web.refuse_url_name name;
  Dynamic (name, f)
let on name handler = Handler (name, handler)

let each ?(equal = Signal.same) ~key items render =
  Each { items; key; equal; render }

module Await = struct
  let make ~async ~loading ?(failed = fun _ -> Fragment []) ~children () =
    Client.use_await ();
    Await { async; loading; failed; render = children }
end

let suspend ~loading ?failed async =
  Await.make ~async ~loading ?failed ~children:(fun e -> e) ()

module Catch = struct
  let make ~fallback ~children () =
    let client at =
      let outer = Option.bind !Base.current_owner (fun o -> o.catch) in
      let failed =
        match at with
        | Some n ->
            let n : Web.node = Obj.obj n in
            Web.node_type n = 8 && Web.data n = "[!"
        | None -> false
      in
      let error = State.make (if failed then Some "server error" else None) in
      let reset () = State.set error None in
      let show (o : Base.owner) m =
        o.catch <- outer;
        fallback ~error:m ~reset
      in
      Hole
        (fun () ->
          let o = Option.get !Base.current_owner in
          match State.get error with
          | Some m -> show o m
          | None -> (
              o.catch <- Some (fun e -> State.set error (Some (Web.exn_to_string e)));
              match Scheduler.untrack children with
              | n -> n
              | exception e ->
                  let m = Web.exn_to_string e in
                  Base.dispose_owner o;
                  error.value <- Some m;
                  show o m))
    in
    Client.use_catch ();
    Catch { children; fallback; client }
end

module Show = struct
  let make ~status ~loading ?(failed = fun _ -> Fragment []) ~children () =
    let view =
      State.memo
        ~equal:(fun a b ->
          match (a, b) with
          | `Data x, `Data y -> Signal.same x y
          | `Loading, `Loading -> true
          | `Failed x, `Failed y -> x = y
          | _ -> false)
        (fun () ->
          match status () with
          | Status.Ready { data; _ } | Loading (Some data) -> `Data data
          | Idle | Loading None -> `Loading
          | Failed { error; _ } -> `Failed error)
    in
    Hole
      (fun () ->
        match State.get view with
        | `Data d -> Scheduler.untrack (fun () -> children d)
        | `Loading -> loading
        | `Failed e -> Scheduler.untrack (fun () -> failed e))
end
