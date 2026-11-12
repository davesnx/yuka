Router.make ~layout:App.root ~not_found:App.not_found
  ~headers:[ ("x-site", "test") ]
  [
    Router.route Home ~path:"/" ~page:App.home ~prerender:true;
    Router.route Docs ~path:"/docs" ~page:App.docs ~prerender:true
      ~headers:[ ("x-twice", "a"); ("x-twice", "b") ];
    Router.group ~path:"/post/:slug<string>" ~loader:App.post ~prerender:true
      [ Router.route Post ~path:"/" ~page:App.post_page ];
    Router.route Secret ~path:"/secret" ~page:App.secret;
    Router.route Page ~path:"/:parts<string...>" ~page:App.page ~prerender:true;
    Router.endpoint Feed ~path:"/feed.xml" ~method_:`GET ~handler:App.feed
      ~prerender:true;
  ]
