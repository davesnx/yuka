open App
open Pages

let root_headers = [ ("x-frame-options", "DENY"); ("x-a", "root") ]
let minute = Yuka.Server.public ~max_age:60 ()
let uncached = Yuka.Server.no_cache

let routes =
  Router.make ~layout:Layouts.root ~not_found ~error ~headers:root_headers ~cache:no_store
    [
      Router.route Home ~path:"/" ~page:home;
      Router.route Plain ~path:"/plain" ~page:plain ~prerender:true;
      Router.route Entry ~path:"/entry" ~page:App.Pages.entry;
      Router.route Search ~path:"/find" ~page:App.Pages.find
        ~search:{ q = optional string; tag = many string };
      Router.route Islands ~path:"/islands" ~page:App.Pages.islands;
      Router.route Slow ~path:"/slow" ~page:App.Pages.slow;
      Router.route Twice ~path:"/twice" ~page:App.Pages.twice;
      Router.route Broken ~path:"/broken" ~page:App.Pages.broken;
      Router.route Boom ~path:"/boom" ~page:App.Pages.boom
        ~loader:App.Loaders.exploding;
      Router.group ~path:"/team/:team<Params.Team.t>" ~layout:App.Layouts.team
        ~guard:App.Guards.outer ~loader:App.Loaders.squad
        ~headers:[ ("X-A", "team") ]
        ~cache:(private_ ~max_age:5) ~prefetch:`Hover
        [
          Router.route Member ~path:"/:user<int>" ~page:App.Pages.member
            ~loader:App.Loaders.profile ~guard:App.Guards.inner;
          Router.route Team_form ~path:"/form" ~page:App.Pages.team_form ~prefetch:`Off;
          Router.route Team_idle ~path:"/idle/:user<int>" ~page:App.Pages.member
            ~loader:App.Loaders.profile ~guard:App.Guards.inner ~prefetch:`Idle;
          Router.route Team_uncached ~path:"/uncached" ~page:App.Pages.team_form
            ~cache:uncached ~prefetch:`Idle;
          Router.route Team_headed ~path:"/headed" ~page:App.Pages.team_form
            ~headers:[ ("Cache-Control", "no-store") ] ~prefetch:`Idle;
          Router.endpoint Team_json ~path:"/json" ~method_:`GET
            ~handler:App.Api.team
            ~cache:(public ~s_max_age:600 ~max_age:60 ());
          Router.action Rename ~path:"/rename" ~method_:`POST
            ~handler:App.Api.rename;
        ];
      Router.route Varied ~path:"/varied" ~page:App.Pages.plain
        ~headers:[ ("Vary", "Cookie") ];
      Router.endpoint Asset ~path:"/asset.txt" ~method_:`GET ~handler:App.Api.asset
        ~cache:immutable;
      Router.route Live_page ~path:"/live" ~page:App.Pages.live;
      Router.route Live_public ~path:"/live-public" ~page:App.Pages.live
        ~cache:(public ~max_age:60 ());
      Router.route Plain_public ~path:"/plain-public" ~page:plain ~cache:minute ~prefetch:`Visible;
      Router.endpoint Cookies ~path:"/cookies" ~method_:`GET ~handler:App.Api.cookies;
      Router.endpoint Bad_header ~path:"/bad-header" ~method_:`GET ~handler:App.Api.bad_header;
      Router.endpoint Put_thing ~path:"/thing" ~method_:`PUT ~handler:App.Api.thing
        ~guard:App.Guards.thing;
      Router.endpoint Hook ~path:"/hook" ~method_:`POST ~handler:App.Api.hook
        ~cross_origin:true;
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
        ~handler:App.Api.clear ~cache:immutable;
      Router.redirect ~path:"/old" ~to_:(Permanent "/");
      Router.redirect ~path:"/tmp/:x<string>" ~to_:(Temporary "/team/:x/json");
    ]
