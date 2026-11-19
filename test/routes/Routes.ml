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
    Router.group ~path:"/issue/:id<Params.issue_id>" ~loader:Loaders.issue
      ~guard:Guards.signed_in
      [
        Router.route Issue ~path:"/" ~page:Pages.issue ?overlay:Pages.issue_dialog
          ~search:
            {
              tab = optional Params.Tab.t;
              seen = many int;
              view = default Params.Tab.t Params.Tab.Overview;
            };
        Router.post Close_issue ~path:"/close"
          ~handler:Actions.close;
        Router.get Issue_json ~path:"/json" ~handler:Api.issue;
        Router.put Update_issue ~path:"/json"
          ~handler:Actions.update;
      ];
    Router.route Page_n ~path:"/page/:n<int>" ~page:Pages.page;
    Router.route Cafe ~path:"/café" ~page:Pages.cafe;
    Router.route Doc ~path:"/docs/:parts<string...>" ~page:Pages.doc;
    Router.get Feed ~path:"/feed.xml" ~handler:Feeds.rss
      ~cache:(Public { max_age = 60; s_max_age = None });
    Router.delete Clear_feed ~path:"/feed.xml"
      ~handler:Actions.clear;
    Router.get Missing ~path:"/missing" ~handler:Api.missing;
    Router.redirect ~path:"/i/:id<Params.issue_id>" ~to_:(Permanent "/issue/:id");
    Router.redirect ~path:"/old-docs/:parts<string...>"
      ~to_:(Temporary "/docs/:parts");
    Router.redirect ~path:"/legacy-blog" ~to_:(Temporary "/blog");
  ]
