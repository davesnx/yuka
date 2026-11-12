let issue (_ : Dream.request) ~id =
  Yuka.Async.return
    (match Store.find id with Some issue -> Ok issue | None -> Error Yuka.Server.Not_found)
