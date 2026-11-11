Router.make ~layout:App.Layouts.root ~not_found:App.Pages.not_found
  ~error:App.Pages.error
  ~headers:[ ("x-frame-options", "DENY"); ("x-a", "root") ]
  ~cache:No_store
  [
    Router.route Home ~path:"/" ~page:App.Pages.home;
    Router.route Plain ~path:"/plain" ~page:App.Pages.plain ~prerender:true;
    Router.route Entry ~path:"/entry" ~page:App.Pages.entry;
    Router.route Find ~path:"/find" ~page:App.Pages.find
      ~search:{ q = optional string; tag = many string };
    Router.route Islands ~path:"/islands" ~page:App.Pages.islands;
    Router.route Slow ~path:"/slow" ~page:App.Pages.slow;
    Router.route Twice ~path:"/twice" ~page:App.Pages.twice;
    Router.route Broken ~path:"/broken" ~page:App.Pages.broken;
    Router.route Boom ~path:"/boom" ~page:App.Pages.boom
      ~loader:App.Loaders.exploding;
    Router.group ~path:"/team/:team<Params.Team>" ~layout:App.Layouts.team
      ~guard:App.Guards.outer ~loader:App.Loaders.squad
      ~headers:[ ("X-A", "team") ]
      ~cache:(Private { max_age = 5 })
      [
        Router.route Member ~path:"/:user<int>" ~page:App.Pages.member
          ~loader:App.Loaders.profile ~guard:App.Guards.inner;
        Router.route Team_form ~path:"/form" ~page:App.Pages.team_form;
        Router.endpoint Team_json ~path:"/json" ~method_:`GET
          ~handler:App.Api.team
          ~cache:(Public { max_age = 60; s_max_age = Some 600 });
        Router.action Rename ~path:"/rename" ~method_:`POST
          ~handler:App.Api.rename;
      ];
    Router.route Varied ~path:"/varied" ~page:App.Pages.plain
      ~headers:[ ("Vary", "Cookie") ];
    Router.endpoint Asset ~path:"/asset.txt" ~method_:`GET ~handler:App.Api.asset
      ~cache:Immutable;
    Router.group ~path:"/org/:org<string>" ~layout:App.Layouts.org
      [
        Router.group ~path:"/x" ~not_found:App.Pages.org_missing
          [
            Router.route Org_item ~path:"/:n<int>" ~page:App.Pages.org_item
              ~loader:App.Loaders.org_item;
          ];
      ];
    Router.endpoint Feed ~path:"/feed.xml" ~method_:`GET ~handler:App.Api.feed
      ~prerender:true;
    Router.endpoint Later ~path:"/later" ~method_:`GET ~handler:App.Api.later;
    Router.action Clear_feed ~path:"/feed.xml" ~method_:`DELETE
      ~handler:App.Api.clear ~cache:Immutable;
    Router.redirect ~path:"/old" ~to_:(Permanent "/");
    Router.redirect ~path:"/tmp/:x<string>" ~to_:(Temporary "/team/:x/json");
  ]
