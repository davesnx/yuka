open Demo_shared

external import : string -> 'a Js.Promise.t = "import"
external register_of : 'a -> Yuka.Client.entry = "register" [@@mel.get]

let load m = Js.Promise.then_ (fun m -> Js.Promise.resolve (register_of m)) m

let () =
  Ui.navigate := Yuka_router_client.navigate;
  Yuka_router_client.start
    ~lazy_entries:
      [
        Yuka_client.lazy_entry ~name:"Demo_shared.Issue_props" (fun () ->
            load (import "../shared/issue_props.js"));
        Yuka_client.lazy_entry ~name:"Demo_shared.Related" (fun () ->
            load (import "../shared/related.js"));
        Yuka_client.lazy_entry ~name:"Demo_shared.Comments" (fun () ->
            load (import "../shared/comments.js"));
      ]
    [ Issue_list.register; Counter.register; New_issue.register ]
