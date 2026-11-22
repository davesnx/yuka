Router.make ~not_found:Pages.not_found ~error:Pages.error
  ~headers:[ ("x-content-type-options", "nosniff") ]
  ~cache:no_store
  [
    Router.group ~path:"/" ~layout:Pages.shell
      [
        Router.route Home ~path:"/" ~page:Pages.home
          ~search:
            {
              seed = optional int;
              columns = optional int;
              rows = optional int;
              half = optional int;
              empty = optional int;
              block = optional int;
              bar = optional int;
              bg = optional string;
              fg = optional string;
              title = optional string;
              subtitle = optional string;
              year = optional string;
              day = optional string;
              weekday = optional string;
            };
      ];
  ]
