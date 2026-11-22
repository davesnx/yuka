let item (_ : Yuka.Server.request) ~id =
  Yuka.Async.return (match Store.find id with Some event -> Ok event | None -> Error Yuka.Server.Not_found)
