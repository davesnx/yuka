Router.make ~not_found:Pages.not_found ~cache:no_store
  [
    Router.route Shelf ~path:"/" ~page:Pages.shelf ~search:{ genre = optional string };
    Router.group ~path:"/album/:id<int>" ~loader:Catalog.album
      [ Router.route Album ~path:"/" ~page:Pages.album ~search:{ track = optional int } ];
  ]
