open Types

type 'kind element = 'kind Kind.element
type 'kind attribute = attr

let text s = Kind.of_node (Text s)
let int n = Kind.of_node (Text (string_of_int n))
let float f =
  Kind.of_node @@ Text
    (if f <> f then "NaN"
     else if f = infinity then "Infinity"
     else if f = neg_infinity then "-Infinity"
     else Json.float_repr f)
let empty = Kind.of_node (Fragment [])
let fragment children = Kind.of_node (Fragment (Kind.nodes children))
let element tag attrs children =
  Client.use_element ();
  Kind.of_node (Element { tag; attrs; children = Kind.nodes children })

let log = Types.log

let valid name =
  Client.use_url_check ();
  if Web.in_browser && not (Url.valid_name name) then invalid_arg ("Yuka: refused attribute name " ^ name)

let url_attr _tag name value =
  valid name;
  Static (name, value)
let attr name value = url_attr "" name value

let attr_unchecked name value =
  Web.refuse_url_name name;
  Static (name, value)
let hole f = Kind.of_node (Hole (Kind.fn f))
let slot s =
  Client.use_slot ();
  Kind.of_node (Slot (Slot_value.to_slot s))

module Slot = struct
  let make content = Slot_value.of_slot { content = Some (Kind.to_node content); dom = ref [] }
end

type stylesheet = string

let stylesheet href = href

let use_css href body =
  if !Base.server_rendering then
    Kind.of_node
      (Fragment
         [ Kind.to_node (element "link" [ Static ("rel", "stylesheet"); Static ("href", href); Static ("data-yuka-css", "") ] []);
           Kind.to_node body ])
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
  Kind.of_node (Each { items; key; equal; render = Kind.fn render })

module Await = struct
  let make ~async ~loading ?(failed = Kind.of_fn (fun _ -> Fragment [])) ~children () =
    Client.use_await ();
    Kind.of_node (Await { async; loading = Kind.to_node loading; failed = Kind.fn failed; render = Kind.fn children })
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
        Kind.to_node (fallback ~error:m ~reset)
      in
      Hole
        (fun () ->
          let o = Option.get !Base.current_owner in
          match State.get error with
          | Some m -> show o m
          | None -> (
              o.catch <- Some (fun e -> State.set error (Some (Web.exn_to_string e)));
              match Scheduler.untrack children with
              | n -> Kind.to_node n
              | exception e ->
                  let m = Web.exn_to_string e in
                  Base.dispose_owner o;
                  error.value <- Some m;
                  show o m))
    in
    Client.use_catch ();
    Kind.of_node (Catch { children = Kind.fn children; fallback = Kind.fallback fallback; client })
end

module Show = struct
  let make ~status ~loading ?(failed = Kind.of_fn (fun _ -> Fragment [])) ~children () =
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
    Kind.of_node
      (Hole
         (fun () ->
           match State.get view with
           | `Data d -> Kind.to_node (Scheduler.untrack (fun () -> children d))
           | `Loading -> Kind.to_node loading
           | `Failed e -> Kind.to_node (Scheduler.untrack (fun () -> failed e))))
end
