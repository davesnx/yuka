Router.make ~not_found:Pages.not_found ~error:Pages.error
  ~headers:[ ("x-content-type-options", "nosniff") ]
  ~cache:no_store
  [
    Router.group ~path:"/" ~layout:Pages.shell ~loader:Loaders.settings
      [
        Router.route Feed ~path:"/" ~page:Pages.feed
          ~search:{ project = many string; team = many string; assignee = many string; before = optional int };
        Router.group ~path:"/item/:id<int>" ~loader:Loaders.item
          [ Router.route Item ~path:"/" ~page:Pages.item ?overlay:Pages.item_panel ];
      ];
  ]
