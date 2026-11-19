include Queries_types

let%action labels =
  Yuka.Action.query ~input:Model.Workspace.codec ~output:(Yuka.Codec.list label_count_codec) (fun _ workspace ->
      Yuka.Async.return (Store.label_counts workspace))
