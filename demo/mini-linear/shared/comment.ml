include Comment_types

let%action add =
  Yuka.Action.mutation ~input:input_codec ~output:codec (fun _ { issue_id; body } ->
      match Store.workspace_of issue_id with
      | None -> Yuka.Server.Action.reject "No such issue"
      | Some workspace ->
          Store.write workspace
            (fun () ->
              match Store.find issue_id with
              | Some issue when String.trim body <> "" -> Ok (Store.add_comment issue ~body)
              | Some _ -> Error "Comment is empty"
              | None -> Error "No such issue")
            Yuka.Async.return)

let%action range =
  Yuka.Action.query ~input:range_codec ~output:(Yuka.Codec.list codec) (fun _ (range : range) ->
      match Store.find range.issue with
      | Some _ when range.offset >= 0 && range.limit >= 0 -> Yuka.Async.return (Store.comment_range range)
      | Some _ -> Yuka.Server.Action.reject "Offset and limit must not be negative"
      | None -> Yuka.Server.Action.reject "No such issue")
