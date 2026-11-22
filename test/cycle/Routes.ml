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
      Router.route Greet ~path:"/greet" ~page:App.Pages.greet
        ~loader:App.Loaders.greeting ~guard:App.Guards.greet;
      Router.post Sum ~path:"/sum" ~handler:App.Api.sum ~guard:App.Guards.sum;
      Router.group ~path:"/team/:team<Params.Team.t>" ~layout:App.Layouts.team
        ~guard:App.Guards.outer ~loader:App.Loaders.squad
        ~headers:[ ("X-A", "team") ]
        ~cache:(private_cache ~max_age:5) ~prefetch:`Hover
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
          Router.get Team_json ~path:"/json"
            ~handler:App.Api.team
            ~cache:(public ~s_max_age:600 ~max_age:60 ());
          Router.post Rename ~path:"/rename"
            ~handler:App.Api.rename;
        ];
      Router.route Varied ~path:"/varied" ~page:App.Pages.plain
        ~headers:[ ("Vary", "Cookie") ];
      Router.get Asset ~path:"/asset.txt" ~handler:App.Api.asset
        ~cache:immutable;
      Router.route Live_page ~path:"/live" ~page:App.Pages.live;
      Router.route Live_public ~path:"/live-public" ~page:App.Pages.live
        ~cache:(public ~max_age:60 ());
      Router.route Plain_public ~path:"/plain-public" ~page:plain ~cache:minute ~prefetch:`Visible;
      Router.get Cookies ~path:"/cookies" ~handler:App.Api.cookies;
      Router.get Bad_header ~path:"/bad-header" ~handler:App.Api.bad_header;
      Router.put Put_thing ~path:"/thing" ~handler:App.Api.thing
        ~guard:App.Guards.thing;
      Router.post Hook ~path:"/hook" ~handler:App.Api.hook
        ~cross_origin:true;
      Router.group ~path:"/org/:org<string>" ~layout:App.Layouts.org ~head:App.Heads.org
        [
          Router.group ~path:"/x" ~not_found:App.Pages.org_missing ~head:App.Heads.x
            [
              Router.route Org_item ~path:"/:n<int>" ~page:App.Pages.org_item
                ?overlay:App.Pages.org_dialog ~loader:App.Loaders.org_item;
            ];
        ];
      Router.get Feed ~path:"/feed.xml" ~handler:App.Api.feed
        ~prerender:true;
      Router.get Later ~path:"/later" ~handler:App.Api.later;
      Router.delete Clear_feed ~path:"/feed.xml"
        ~handler:App.Api.clear;
      Router.group ~path:"/:locale<I18n_shared.Messages.locale>" ~layout:App.Layouts.locale
        [ Router.route Hello ~path:"/hello" ~page:App.Pages.hello ];
      Router.redirect ~path:"/old" ~to_:(Permanent "/");
      Router.redirect ~path:"/tmp/:x<string>" ~to_:(Temporary "/team/:x/json");
    ]
