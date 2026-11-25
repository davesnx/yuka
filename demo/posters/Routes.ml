Router.make ~not_found:Pages.not_found ~error:Pages.error
  ~headers:[ ("x-content-type-options", "nosniff") ]
  ~cache:no_store
  [
    Router.group ~path:"/" ~layout:Pages.shell
      [
        Router.route Home ~path:"/" ~page:Pages.home
          ~search:
            {
              kind = optional Pattern.Kind.t;
              seed = optional int;
              padding = optional int;
              lines = optional int;
              amplitude = optional int;
              waves = optional int;
              stroke = optional int;
              direction = optional int;
              blocks = optional int;
              gap = optional int;
              filled = optional int;
              squareness = optional int;
              radius = optional int;
              clouds = optional int;
              puffs = optional int;
              size = optional int;
              bolts = optional int;
              branches = optional int;
              jaggedness = optional int;
              thickness = optional int;
              length = optional int;
              style = optional Pattern.Style.t;
              columns = optional int;
              rows = optional int;
              half = optional int;
              empty = optional int;
              block = optional int;
              bar = optional int;
              merge = optional int;
              round = optional int;
              accent = optional int;
              tint = optional string;
              bg = optional string;
              fg = optional string;
              title = optional string;
              subtitle = optional string;
              year = optional string;
              day = optional string;
              weekday = optional string;
            };
        Router.route Gallery ~path:"/gallery" ~page:Pages.gallery ~prerender:true;
      ];
    Router.get Poster_svg ~path:"/poster.svg" ~handler:Handlers.poster_svg ~cache:(public ~max_age:3600 ());
  ]
