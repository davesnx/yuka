Router.make ~not_found:Pages.not_found ~error:Pages.error
  ~headers:[ ("x-content-type-options", "nosniff") ]
  ~cache:no_store
  [
    Router.group ~path:"/" ~layout:Pages.shell
      [
        Router.route Title ~path:"/" ~page:Pages.title;
        Router.route Scene ~path:"/scene/:id<string>" ~loader:Loaders.scene ~page:Pages.scene;
      ];
  ]
