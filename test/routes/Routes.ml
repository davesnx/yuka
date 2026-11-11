Router.make ~layout:Layouts.root ~not_found:Pages.not_found ~error:Pages.error
  ~headers:[ ("x-frame-options", "DENY") ]
  ~cache:No_store
  [
    Router.route Home ~path:"/" ~page:Pages.home ~prerender:true;
    Router.group ~path:"/blog" ~layout:Layouts.blog
      ~search:{ lang = optional string }
      [
        Router.route Blog ~path:"/" ~page:Pages.blog
          ~search:
            {
              tag = optional string;
              page = default int 1;
              label = many string;
              draft = default bool false;
            };
        Router.route Post ~path:"/:slug<string>" ~page:Pages.post
          ~loader:Loaders.post;
        Router.route New_post ~path:"/new" ~page:Pages.new_post;
      ];
    Router.group ~path:"/issue/:id<Params.Issue_id>" ~loader:Loaders.issue
      ~guard:Guards.signed_in
      [
        Router.route Issue ~path:"/" ~page:Pages.issue
          ~search:
            {
              tab = optional Params.Tab;
              seen = many int;
              view = default Params.Tab Params.Tab.Overview;
            };
        Router.action Close_issue ~path:"/close" ~method_:`POST
          ~handler:Actions.close;
        Router.endpoint Issue_json ~path:"/json" ~method_:`GET ~handler:Api.issue;
        Router.action Update_issue ~path:"/json" ~method_:`PUT
          ~handler:Actions.update;
      ];
    Router.route Page_n ~path:"/page/:n<int>" ~page:Pages.page;
    Router.route Cafe ~path:"/café" ~page:Pages.cafe;
    Router.route Doc ~path:"/docs/:parts<string...>" ~page:Pages.doc;
    Router.endpoint Feed ~path:"/feed.xml" ~method_:`GET ~handler:Feeds.rss
      ~cache:(Public { max_age = 60; s_max_age = None });
    Router.action Clear_feed ~path:"/feed.xml" ~method_:`DELETE
      ~handler:Actions.clear;
    Router.endpoint Missing ~path:"/missing" ~method_:`GET ~handler:Api.missing;
    Router.redirect ~path:"/i/:id<Params.Issue_id>" ~to_:(Permanent "/issue/:id");
    Router.redirect ~path:"/old-docs/:parts<string...>"
      ~to_:(Temporary "/docs/:parts");
    Router.redirect ~path:"/legacy-blog" ~to_:(Temporary "/blog");
  ]
