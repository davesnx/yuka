let context : string State.read Element.Context.t option ref = ref None

let get () =
  match !context with
  | Some c -> c
  | None ->
      let c = Element.Context.make ~name:Types.route_name ~codec:(Codec.state Codec.string) () in
      context := Some c;
      c

let typed find url =
  let path, _ = Router.split_target url in
  match find `GET (List.map (Router.decode ~plus:false) (Router.split_path path)) (Router.query url) with
  | Router.Found r -> Some r
  | Router.Wrong_method _ | Router.Redirect _ | Router.Missing -> None

let current find =
  match Element.Context.get (get ()) with
  | Some url -> State.memo (fun () -> typed find (State.get url))
  | None -> State.read_only (State.make None)

let moved () = Page_context.set "route" Types.route_name (`String (Web.current_url ()))
let same_page url = String.equal (fst (Router.split_target url)) (fst (Router.split_target (Web.current_url ())))

let replace url =
  if same_page url then begin
    Web.history_replace_url url;
    Platform.loaded := Web.current_url ();
    moved ()
  end
  else Browser.navigate url

let push url =
  if same_page url then begin
    let before = Web.history_key () and key = Web.fresh_key () in
    Navigation_web.history_push_key key url;
    Navigation_stub.current_key := key;
    Platform.kept := key :: before :: !Platform.kept;
    Platform.moved := moved;
    Platform.loaded := Web.current_url ();
    moved ()
  end
  else Browser.navigate url
