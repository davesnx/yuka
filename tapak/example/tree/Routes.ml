Router.make ~not_found:App.not_found
  [
    Router.route Home ~path:"/" ~page:App.home;
    Router.route Slow ~path:"/slow" ~page:App.slow;
    Router.endpoint Hello ~path:"/hello.json" ~method_:`GET ~handler:App.hello;
  ]
