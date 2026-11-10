open Types
include Form_core

type ('i, 'o, 'f) action = ('i, ('o, 'f errors) result, [ `Mutation ]) Action.t

let pairs_json values : Json.t = `List (List.map (fun (k, v) -> `List [ `String k; `String v ]) values)

let all f items =
  List.fold_right (fun x acc -> match (f x, acc) with Some y, Some ys -> Some (y :: ys) | _ -> None) items (Some [])

let pairs_of_json = function
  | `List items -> all (function `List [ `String k; `String v ] -> Some (k, v) | _ -> None) items
  | _ -> None

let names_json errors : Json.t =
  `List
    (List.map
       (fun (n, m) -> `List [ (match n with Some n -> `String n | None -> `Null); `String m ])
       errors)

let names_of_json (j : Json.t) =
  let item = function
    | `List [ `String n; `String m ] -> Some (Some n, m)
    | `List [ `Null; `String m ] -> Some (None, m)
    | _ -> None
  in
  match j with
  | `List items -> ( match all item items with Some e -> Ok e | None -> Codec.mismatch "form errors" j)
  | _ -> Codec.mismatch "form errors" j

type 'o answer = { result : ('o, (string option * string) list) result; redirect : string option }

let read_answer (output : 'o Codec.t) (j : Json.t) : ('o answer, string) result =
  match j with
  | `Assoc fields -> (
      match (List.assoc_opt "value" fields, List.assoc_opt "errors" fields) with
      | Some v, _ ->
          Result.map
            (fun o ->
              {
                result = Ok o;
                redirect = (match List.assoc_opt "redirect" fields with Some (`String l) -> Some l | _ -> None);
              })
            (output.decode v)
      | None, Some e -> Result.map (fun e -> { result = Error e; redirect = None }) (names_of_json e)
      | None, None -> Codec.mismatch "form answer" j)
  | _ -> Codec.mismatch "form answer" j

let action ~name ~fields:t ~(output : 'o Codec.t) : ('i, 'o, 'f) action =
  let input : _ Codec.t =
    {
      encode = (fun i -> pairs_json (encode t i));
      decode =
        (fun j ->
          match pairs_of_json j with
          | None -> Codec.mismatch "form fields" j
          | Some values -> (
              match decode t values with
              | Ok i -> Ok i
              | Error e -> Error (String.concat "; " (List.map snd e))));
    }
  in
  let result : ('o, _) result Codec.t =
    {
      encode =
        (function
        | Ok o -> `Assoc [ ("value", output.encode o) ]
        | Error e -> `Assoc [ ("errors", names_json (named t e)) ]);
      decode =
        (fun j ->
          Result.map
            (fun a -> match a.result with Ok o -> Ok o | Error e -> Error (unnamed t e))
            (read_answer output j));
    }
  in
  { Action.name; input; output = result; form = Some (Action.Form t) }

type ('o, 'f) form = {
  sent : (string * string) list;
  failed : 'f errors State.t;
  busy : bool State.t;
  field_name : 'f -> string;
}

let value form f = Option.value (List.assoc_opt (form.field_name f) form.sent) ~default:""

let error form f =
  List.find_map
    (fun (g, m) -> match g with Some g when g == f -> Some m | _ -> None)
    (State.get form.failed)

let form_errors form = List.filter_map (fun (g, m) -> match g with None -> Some m | Some _ -> None) (State.get form.failed)
let error_view form f view = Hole (fun () -> match error form f with Some m -> view m | None -> Fragment [])
let form_error_view form view = Hole (fun () -> Fragment (List.map view (form_errors form)))
let pending form = State.get form.busy
let read_key = "__yuka_sent_read"

let read_sent name key =
  List.find_map
    (fun el ->
      let read : bool option = Web.get_prop el read_key in
      if
        read = Some true
        || Web.get_attribute el "data-yuka-action" <> Some name
        || Web.get_attribute el "data-yuka-key" <> Some key
      then None
      else
        let sent = Option.value (Web.get_attribute el "data-yuka-sent") ~default:"" in
        match Json.of_string sent with
        | Ok (`Assoc fields) -> (
            match
              ( Option.bind (List.assoc_opt "fields" fields) pairs_of_json,
                Option.map names_of_json (List.assoc_opt "errors" fields) )
            with
            | Some values, Some (Ok errors) ->
                Web.set_bool el read_key true;
                Some (values, errors)
            | _ -> invalid_arg ("Yuka.Form: bad data-yuka-sent " ^ sent))
        | _ -> invalid_arg ("Yuka.Form: bad data-yuka-sent " ^ sent))
    (Array.to_list (Web.query_all (Web.document ()) "form[data-yuka-sent]"))

let sent_state name key =
  match !current_session with
  | Some s -> (
      match s.form with
      | Some (n, k, values, errors) when String.equal n name && String.equal k key -> Some (values, errors)
      | _ -> None)
  | None when Web.in_browser -> read_sent name key
  | None -> None

let make (type i o f) ~(action : (i, (o, f errors) result, [ `Mutation ]) Action.t) ?(key = "") ?run ?on_ok
    ~(children : (o, f) form -> 'k) () =
  let t : (i, f) Form_core.t =
    match action.form with
    | Some (Action.Form t) -> t
    | None -> invalid_arg ("Yuka.Form.make: " ^ action.name ^ " is not a form action")
  in
  let sent = sent_state action.name key in
  let form =
    {
      sent = (match sent with Some (v, _) -> v | None -> []);
      failed = State.make (match sent with Some (_, e) -> unnamed t e | None -> []);
      busy = State.make false;
      field_name = name t;
    }
  in
  let follow = function
    | Some location -> Platform.Browser.navigate location
    | None -> Platform.Browser.navigate (Web.current_url ())
  in
  let finish result redirect =
    State.set form.busy false;
    match result with
    | Ok (Ok o) -> ( match on_ok with Some f -> f o | None -> follow redirect)
    | Ok (Error e) -> State.set form.failed e
    | Error m -> State.set form.failed [ (None, m) ]
  in
  let call input =
    let json = action.input.encode input in
    Async.on_result (!Action.transport action.name json) (function
      | Error m -> finish (Error m) None
      | Ok j -> (
          let redirect =
            match j with
            | `Assoc fields -> (
                match List.assoc_opt "redirect" fields with Some (`String l) -> Some l | _ -> None)
            | _ -> None
          in
          match action.output.decode j with
          | Ok r -> finish (Ok r) redirect
          | Error m -> finish (Error m) None))
  in
  let submit ev =
    Web.prevent_default ev;
    match decode t (Array.to_list (Web.form_values ev)) with
    | Error e -> State.set form.failed e
    | Ok input -> (
        State.set form.failed [];
        State.set form.busy true;
        match run with
        | Some f -> Async.on_result (f input) (fun r -> finish r None)
        | None -> call input)
  in
  let sent_attr =
    match sent with
    | Some (values, errors) ->
        [ Static ("data-yuka-sent", Json.to_string (`Assoc [ ("fields", pairs_json values); ("errors", names_json errors) ])) ]
    | None -> []
  in
  let hidden name value =
    Element { tag = "input"; attrs = [ Static ("type", "hidden"); Static ("name", name); Static ("value", value) ]; children = [] }
  in
  Element
    {
      tag = "form";
      attrs =
        [ Static ("method", "post"); Static ("data-yuka-action", action.name); Static ("data-yuka-key", key) ]
        @ sent_attr
        @ [ Handler ("submit", submit) ];
      children =
        (hidden "_yuka_action" action.name :: (if key = "" then [] else [ hidden "_yuka_key" key ]))
        @ [ children form ];
    }
