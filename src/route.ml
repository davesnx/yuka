let context : string State.read Element.Context.t option ref = ref None

let get () =
  match !context with
  | Some c -> c
  | None ->
      let c = Element.Context.make ~name:Types.route_name ~codec:(Codec.state Codec.string) () in
      context := Some c;
      c

let typed find url =
  match Site.strip (Site.base ()) url with
  | None -> None
  | Some url -> (
      let path, _ = Router.split_target url in
      match find `GET (List.map (Router.decode ~plus:false) (Router.split_path path)) (Router.query url) with
      | Router.Found r -> Some r
      | Router.Wrong_method _ | Router.Redirect _ | Router.Missing -> None)

let current find =
  match Element.Context.get (get ()) with
  | Some url -> State.memo (fun () -> typed find (State.get url))
  | None -> State.read_only (State.make None)

let pending find =
  State.memo (fun () ->
      match State.get Browser.navigation with Some n -> typed find n.Browser.url | None -> None)

let moved () = Page_context.set "route" Types.route_name (`String (Host.current_url ()))
let same_page url = String.equal (fst (Router.split_target url)) (fst (Router.split_target (Host.current_url ())))

let replace url =
  if same_page url then begin
    Host.history_replace_url url;
    Platform.loaded := Host.current_url ();
    moved ()
  end
  else Browser.navigate ~replace:true url

let push url =
  if same_page url then begin
    Navigation_stub.save_scroll ();
    let before = Host.history_key () and key = Host.fresh_key () in
    Host.history_push_key key url;
    Navigation_stub.current_key := key;
    Navigation_stub.at := Host.history_at ();
    Navigation_stub.shown_key := key;
    Platform.kept := key :: before :: !Platform.kept;
    Platform.moved := moved;
    Platform.loaded := Host.current_url ();
    moved ()
  end
  else Browser.navigate url
