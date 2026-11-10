Router.make ~not_found:Pages.not_found ~error:Pages.error
  ~headers:[ ("x-content-type-options", "nosniff") ]
  ~cache:No_store
  [
    Router.route About ~path:"/about" ~page:Pages.about ~prerender:true;
    Router.group ~path:"/" ~layout:Pages.shell ~not_found:Pages.not_found
      ~error:Pages.error
      [
        Router.route Issues ~path:"/" ~page:Pages.index;
        Router.route My_issues ~path:"/my" ~page:Pages.my_issues;
        Router.route Create ~path:"/new" ~page:Pages.create;
        Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue
          ~not_found:Pages.issue_not_found
          [ Router.route Issue ~path:"/" ~page:Pages.issue ];
      ];
    Router.endpoint Issues_json ~path:"/issues.json" ~method_:`GET
      ~handler:Handlers.issues_json
      ~cache:(Public { max_age = 60; s_max_age = None });
    Router.redirect ~path:"/issues" ~to_:(Permanent "/");
  ]
