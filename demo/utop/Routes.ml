Router.make ~not_found:Pages.not_found ~cache:no_store
  [ Router.route Session ~path:"/" ~page:Pages.session ~search:{ file = optional string } ]
