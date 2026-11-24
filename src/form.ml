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
            (Codec.decode output v)
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
        | Ok o -> `Assoc [ ("value", Codec.encode output o) ]
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
  error_id : 'f -> string;
}

let value form f = Option.value (List.assoc_opt (form.field_name f) form.sent) ~default:""

let errors form = State.read_only form.failed
let field_error (errors : _ errors) f = List.find_map (fun (g, m) -> match g with Some g when g == f -> Some m | _ -> None) errors
let form_errors (errors : _ errors) = List.filter_map (fun (g, m) -> match g with None -> Some m | Some _ -> None) errors

let field_error_view form f view =
  Kind.of_node
    (Hole
       (fun () ->
         match field_error (State.get form.failed) f with
         | Some m -> Kind.to_node (view ~id:(form.error_id f) m)
         | None -> Fragment []))

let form_errors_view form view =
  let autofocus =
    !(Base.server_rendering ())
    && match State.get form.failed with [] -> false | e -> List.for_all (fun (g, _) -> Option.is_none g) e
  in
  Element.element "div"
    ([ Static ("role", "alert"); Static ("tabindex", "-1"); Static ("data-yuka-errors", "") ]
    @ if autofocus then [ Static ("autofocus", "") ] else [])
    [ Kind.of_node (Hole (fun () -> Fragment (List.map (Kind.fn view) (form_errors (State.get form.failed))))) ]

let pending form = State.read_only form.busy
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

let forms_of name key =
  List.filter
    (fun el -> Web.DOM.Element.getAttribute "data-yuka-action" el = Some name && Web.DOM.Element.getAttribute "data-yuka-key" el = Some key)
    (Array.to_list (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll "form[data-yuka-action]" Web.DOM.document)))

let mark ~action ~key ~focus ~whole names form_el =
  let focused = ref (not focus) in
  Array.iter
    (fun el ->
      match (Web.DOM.Element.localName el, Web.DOM.Element.getAttribute "name" el) with
      | ("input" | "select" | "textarea"), Some name ->
          let id = error_id ~action ~key name in
          let tokens = String.split_on_char ' ' (Option.value (Web.DOM.Element.getAttribute "aria-describedby" el) ~default:"") in
          let others = List.filter (fun token -> token <> "" && token <> id) tokens in
          if List.exists (String.equal name) names then begin
            Web.DOM.Element.setAttribute ~name:"aria-invalid" ~value:"true" el;
            Web.DOM.Element.setAttribute ~name:"aria-describedby" ~value:(String.concat " " (others @ [ id ])) el;
            match (Web.DOM.Element.getAttribute "type" el) with
            | Some "hidden" -> ()
            | _ when !focused -> ()
            | _ ->
                focused := true;
                Host.focus_node el
          end
          else if List.mem id tokens then begin
            Web.DOM.Element.removeAttribute "aria-invalid" el;
            match others with
            | [] -> Web.DOM.Element.removeAttribute "aria-describedby" el
            | _ -> Web.DOM.Element.setAttribute ~name:"aria-describedby" ~value:(String.concat " " others) el
          end
      | _ -> ())
    (Web.DOM.NodeList.toArray (Web.DOM.Element.querySelectorAll "[name]" form_el));
  if whole && not !focused then
    match (Web.DOM.NodeList.toArray (Web.DOM.Element.querySelectorAll "[data-yuka-errors]" form_el)) with [||] -> () | found -> Host.focus_node found.(0)

let read_sent name key =
  List.find_map
    (fun el ->
      let sent = Option.value (Web.DOM.Element.getAttribute "data-yuka-sent" el) ~default:"" in
      match parse_sent sent with
      | Some state -> Some state
      | None ->
          if Dev.on then Host.console_error ("yuka: ignored a bad data-yuka-sent on form " ^ name ^ ": " ^ sent);
          None)
    (List.filter (fun el -> Option.is_some (Web.DOM.Element.getAttribute "data-yuka-sent" el)) (forms_of name key))

let sent_state name key =
  match !(current_session ()) with
  | Some s -> (
      match s.form with
      | Some (n, k, values, errors) when String.equal n name && String.equal k key -> Some (values, errors)
      | _ -> None)
  | None when Host.in_browser -> read_sent name key
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
      error_id = (fun f -> error_id ~action:(Action.name action) ~key (name t f));
    }
  in
  let first = ref true in
  let gone = ref false in
  Base.own (fun () -> gone := true);
  let rec submit ev =
    Web.DOM.Event.preventDefault ev;
    Web.DOM.Element.removeAttribute "data-yuka-sent" (Host.target_element (Web.DOM.Event.target ev));
    match decode t (Array.to_list (Host.form_values ev)) with
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
  and finish result redirect =
    if not !gone then begin
      State.set form.busy false;
      match result with
      | Ok (Ok o) -> ( match on_ok with Some f -> f o | None -> follow redirect)
      | Ok (Error e) -> State.set form.failed e
      | Error m -> State.set form.failed [ (None, m) ]
    end
  and failed e = finish (Error (Status.error_to_string e)) None
  and call input =
    let json = Codec.encode (Action.input action) input in
    let (_ : unit -> unit) =
      Action.send (Action.name action) json (function
        | Ok j -> (
            match read_answer output j with
            | Ok { result; redirect } -> finish (Ok (Result.map_error (unnamed t) result)) redirect
            | Error m -> finish (Error m) None)
        | Error e -> failed e)
    in
    ()
  and follow = function
    | Some location when not (Host.same_origin location) ->
        if Dev.on then Host.console_error ("yuka: refused a redirect to another site: " ^ location);
        State.set form.failed [ (None, Status.error_to_string (Protocol "refused a redirect")) ]
    | Some location -> Browser.navigate location
    | None -> Browser.refresh ()
  in
  Base.Effect.after (fun () ->
      let failed = State.get form.failed in
      let names = List.filter_map (function Some f, _ -> Some (name t f) | None, _ -> None) failed in
      let whole = List.exists (fun (g, _) -> Option.is_none g) failed in
      let focus = not !first in
      if !first && Dev.on && List.length (forms_of (Action.name action) key) > 1 then
        Host.console_error
          ("yuka: two forms on this page have the action " ^ Action.name action ^ " and the key \"" ^ key
         ^ "\": give each a different key");
      first := false;
      if (match names with [] -> focus | _ -> true) then
        List.iter
          (mark ~action:(Action.name action) ~key ~focus ~whole names)
          (List.filter
             (fun el -> Client.has_handler el "submit" submit)
             (Array.to_list (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll "form[data-yuka-action]" Web.DOM.document)))));
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
