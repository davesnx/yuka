Router.make ~not_found:Pages.not_found ~cache:no_store
  [
    Router.route Home ~path:"/" ~page:Pages.home
      ~search:{ seed = optional int; grid = optional int; stroke = optional int; palette = optional int };
  ]
