open Demo_shared

let routes =
  Router.make ~not_found:Pages.not_found ~error:Pages.error
    ~headers:[ ("x-content-type-options", "nosniff") ]
    ~cache:no_store
    [
      Router.route About ~path:"/about" ~page:Pages.about ~prerender:true;
      Router.route Before_hydration ~path:"/before-hydration" ~page:Pages.before_hydration;
      Router.group ~path:"/" ~layout:Pages.shell ~not_found:Pages.not_found
        ~error:Pages.error
        [
          Router.route Issues ~path:"/" ~page:Pages.index ~search:{ q = optional string; label = many string };
          Router.route My_issues ~path:"/my" ~page:Pages.my_issues ~search:{ q = optional string; label = many string };
          Router.route Insights ~path:"/insights" ~page:Pages.insights;
          Router.route Create ~path:"/new" ~page:Pages.create;
          Router.group ~path:"/issue/:id<string>" ~loader:Loaders.issue
            ~not_found:Pages.issue_not_found
            [ Router.route Issue ~path:"/" ~page:Pages.issue ];
        ];
      Router.group ~path:"/w/:workspace<Model.Workspace.t>" ~layout:Pages.Workspace.shell
        [
          Router.route Workspace_issues ~path:"/" ~page:Pages.Workspace.index
            ~search:{ q = optional string; label = many string };
          Router.route Workspace_my_issues ~path:"/my" ~page:Pages.Workspace.my_issues
            ~search:{ q = optional string; label = many string };
          Router.route Workspace_insights ~path:"/insights" ~page:Pages.Workspace.insights;
          Router.route Workspace_create ~path:"/new" ~page:Pages.Workspace.create;
          Router.group ~path:"/issue/:id<string>" ~loader:Loaders.Workspace.issue
            ~not_found:Pages.Workspace.issue_not_found
            [ Router.route Workspace_issue ~path:"/" ~page:Pages.Workspace.issue ];
        ];
      Router.endpoint Issues_json ~path:"/issues.json" ~method_:`GET
        ~handler:Handlers.issues_json
        ~cache:(public ~max_age:60 ());
      Router.redirect ~path:"/issues" ~to_:(Permanent "/");
    ]
