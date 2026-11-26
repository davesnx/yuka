Router.make ~not_found:Pages.not_found ~cache:no_store
  [ Router.route Host ~path:"/" ~page:Pages.host ~search:{ host = optional string } ]
