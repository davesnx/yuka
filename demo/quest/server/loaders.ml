let scene (_ : Yuka.Server.request) ~id =
  Yuka.Async.return (match Story.find id with Some scene -> Ok scene | None -> Error Yuka.Server.Not_found)
