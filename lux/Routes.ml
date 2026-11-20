Router.make
  [
    Router.route Index ~path:"/" ~page:Pages.index;
    Router.route Dom ~path:"/dom" ~page:Pages.dom ~search:{ n = default int 64 };
  ]
