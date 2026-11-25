Router.make ~layout:App.root ~not_found:App.not_found
  ~headers:[ ("x-site", "test") ]
  [
    Router.route Home ~path:"/" ~page:App.home ~prerender:true;
    Router.route Docs ~path:"/docs" ~page:App.docs ~prerender:true
      ~headers:[ ("x-twice", "a"); ("x-twice", "b") ];
    Router.group ~path:"/post/:slug<string>" ~loader:App.post ~prerender:true
      [ Router.route Post ~path:"/" ~page:App.post_page ];
    Router.route Secret ~path:"/secret" ~page:App.secret;
    Router.route Warned ~path:"/warned" ~page:App.warned;
    Router.route Slow ~path:"/slow" ~page:App.slow;
    Router.route Stuck ~path:"/stuck" ~page:App.stuck;
    Router.route Gated ~path:"/gated" ~page:App.gated;
    Router.get Whoami ~path:"/whoami" ~handler:App.whoami;
    Router.get Session ~path:"/session" ~handler:App.session;
    Router.post Sum ~path:"/sum" ~handler:App.sum;
    Router.patch Patched ~path:"/patched" ~handler:App.patched;
    Router.get Ticks ~path:"/ticks" ~handler:App.ticks;
    Router.get Flood ~path:"/flood" ~handler:App.flood;
    Router.get Framing ~path:"/framing" ~handler:App.framing;
    Router.route Page ~path:"/:parts<string...>" ~page:App.page ~prerender:true;
    Router.get Feed ~path:"/feed.xml" ~handler:App.feed ~prerender:true;
  ]
