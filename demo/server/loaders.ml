let issue (_ : Dream.request) ~id =
  Yuka.Async.resolved
    (match Store.find id with Some i -> Ok i | None -> Error Yuka.Server.Not_found)
