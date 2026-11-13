open Types
include Form_core

type ('i, 'o, 'f) action = ('i, ('o, 'f errors) result, [ `Form ]) Action.t

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
  | `List items -> ( match all item items with Some e -> Ok e | None -> Json.mismatch "form errors" j)
  | _ -> Json.mismatch "form errors" j

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
      | None, None -> Json.mismatch "form answer" j)
  | _ -> Json.mismatch "form answer" j

let action ~name ~fields:t ~(output : 'o Codec.t) : ('i, 'o, 'f) action =
  let input : _ Codec.t =
    Codec.make
      ~encode:((fun i -> pairs_json (encode t i)))
      ~decode:((fun j ->
          match pairs_of_json j with
          | None -> Json.mismatch "form fields" j
          | Some values -> (
              match decode t values with
              | Ok i -> Ok i
              | Error e -> Error (String.concat "; " (List.map snd e)))))
  in
  let result : ('o, _) result Codec.t =
    Codec.make
      ~encode:((function
        | Ok o -> `Assoc [ ("value", output.encode o) ]
        | Error e -> `Assoc [ ("errors", names_json (named t e)) ]))
      ~decode:((fun j ->
          Result.map
            (fun a -> match a.result with Ok o -> Ok o | Error e -> Error (unnamed t e))
            (read_answer output j)))
  in
  Action.with_form ~name ~input ~output:result (Action.Form (t, output))

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

let errors form = List.filter_map (fun (g, m) -> match g with None -> Some m | Some _ -> None) (State.get form.failed)
let error_view form f view =
  Kind.of_node (Hole (fun () -> match error form f with Some m -> Kind.to_node (view m) | None -> Fragment []))

let errors_view form view =
  Kind.of_node (Hole (fun () -> Fragment (List.map (Kind.fn view) (errors form))))
let pending form = State.get form.busy
let parse_sent sent =
  match Json.of_string sent with
  | Ok (`Assoc fields) -> (
      match
        ( Option.bind (List.assoc_opt "fields" fields) pairs_of_json,
          Option.map names_of_json (List.assoc_opt "errors" fields) )
      with
      | Some values, Some (Ok errors) -> Some (values, errors)
      | _ -> None)
  | _ -> None

let read_sent name key =
  List.find_map
    (fun el ->
      if Web.get_attribute el "data-yuka-action" <> Some name || Web.get_attribute el "data-yuka-key" <> Some key
      then None
      else
        let sent = Option.value (Web.get_attribute el "data-yuka-sent") ~default:"" in
        match parse_sent sent with
        | Some state -> Some state
        | None ->
            if Dev.on then Web.console_error ("yuka: ignored a bad data-yuka-sent on form " ^ name ^ ": " ^ sent);
            None)
    (Array.to_list (Web.query_all (Web.document ()) "form[data-yuka-sent]"))

let sent_state name key =
  match !current_session with
  | Some s -> (
      match s.form with
      | Some (n, k, values, errors) when String.equal n name && String.equal k key -> Some (values, errors)
      | _ -> None)
  | None when Web.in_browser -> read_sent name key
  | None -> None

let make (type i o f) ~(action : (i, o, f) action) ?(key = "") ?run ?on_ok ~(children : (o, f) form -> 'k) () =
  let (Action.Form (t, output)) = Action.form action in
  let t : (i, f) Form_core.t = t and output : o Codec.t = output in
  let sent = sent_state (Action.name action) key in
  let form =
    {
      sent = (match sent with Some (v, _) -> v | None -> []);
      failed = State.make (match sent with Some (_, e) -> unnamed t e | None -> []);
      busy = State.make false;
      field_name = name t;
    }
  in
  let follow = function
    | Some location when not (Web.same_origin location) ->
        State.set form.failed [ (None, "Yuka: refused a redirect to another site: " ^ location) ]
    | Some location -> Browser.navigate location
    | None -> Browser.navigate (Web.current_url ())
  in
  let finish result redirect =
    State.set form.busy false;
    match result with
    | Ok (Ok o) -> ( match on_ok with Some f -> f o | None -> follow redirect)
    | Ok (Error e) -> State.set form.failed e
    | Error m -> State.set form.failed [ (None, m) ]
  in
  let failed e = finish (Error (Status.error_to_string e)) None in
  let call input =
    let json = (Action.input action).encode input in
    Async.on_result (Action.send (Action.name action) json) (function
      | Ok (Ok j) -> (
          match read_answer output j with
          | Ok { result; redirect } -> finish (Ok (Result.map_error (unnamed t) result)) redirect
          | Error m -> finish (Error m) None)
      | Ok (Error e) -> failed e
      | Error m -> finish (Error m) None)
  in
  let submit ev =
    Web.prevent_default ev;
    Web.remove_attribute (Web.target ev) "data-yuka-sent";
    match decode t (Array.to_list (Web.form_values ev)) with
    | Error e -> State.set form.failed e
    | Ok input -> (
        State.set form.failed [];
        State.set form.busy true;
        match run with
        | Some f ->
            Async.on_result (f input) (function
              | Ok (Ok r) -> finish (Ok r) None
              | Ok (Error e) -> failed e
              | Error m -> finish (Error m) None)
        | None -> call input)
  in
  let sent_attr =
    match sent with
    | Some (values, errors) ->
        [ Static ("data-yuka-sent", Json.to_string (`Assoc [ ("fields", pairs_json values); ("errors", names_json errors) ])) ]
    | None -> []
  in
  let hidden name value =
    Element.element "input" [ Static ("type", "hidden"); Static ("name", name); Static ("value", value) ] []
  in
  Element.element "form"
    ([ Static ("method", "post"); Static ("data-yuka-action", Action.name action); Static ("data-yuka-key", key) ]
    @ sent_attr
    @ [ Handler ("submit", submit) ])
    ((hidden "_yuka_action" (Action.name action) :: (if key = "" then [] else [ hidden "_yuka_key" key ]))
    @ [ children form ])
