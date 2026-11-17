Router.make ~not_found:App.not_found
  [
    Router.route Home ~path:"/" ~page:App.home;
    Router.route Slow ~path:"/slow" ~page:App.slow;
    Router.get Hello ~path:"/hello.json" ~handler:App.hello;
  ]
