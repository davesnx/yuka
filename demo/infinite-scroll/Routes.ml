Router.make ~not_found:Pages.not_found ~cache:no_store
  [ Router.route Gallery ~path:"/" ~page:Pages.gallery ~search:{ pages = default int 1 } ]
