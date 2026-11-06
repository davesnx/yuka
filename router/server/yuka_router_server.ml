let handler ?(not_found = fun _ -> Dream.empty `Not_Found) cases request =
  match Yuka_router.dispatch cases (Dream.target request) with
  | Some h -> h request
  | None -> not_found request
