open Demo_shared
open Theme_menu
module State = Yuka.State

let swatch_theme =
  Block_stubs.template ~markup:"<span></span>" ~walk:[||] ~targets:[| 0; 0 |]
    ~kinds:[| Block_stubs.Class; Block_stubs.Attr "data-theme" |]

let swatch_auto =
  Block_stubs.template ~markup:"<span></span>" ~walk:[||] ~targets:[| 0; 0 |]
    ~kinds:[| Block_stubs.Class; Block_stubs.Attr "data-theme" |]

let swatch_code =
  Block_stubs.template ~markup:"<span></span>" ~walk:[||] ~targets:[| 0; 0 |]
    ~kinds:[| Block_stubs.Class; Block_stubs.Attr "data-code" |]

let check =
  Block_stubs.template
    ~markup:
      {|<svg viewBox="0 0 14 14" width="14" height="14" aria-hidden="true"><path d="M3 7.5 L6 10.5 L11 4" fill="none" stroke="currentColor" stroke-width="1.75"></path></svg>|}
    ~walk:[||] ~targets:[| 0 |] ~kinds:[| Block_stubs.Attr "class" |]

let item_template =
  Block_stubs.template ~markup:{|<button class="menu-item" type="button" role="menuitemradio"><!----> <!----></button>|}
    ~walk:[| 0; 0; 3; 1; 5; 1 |] ~targets:[| 0; 0; 0; 0; 1; 2; 3 |]
    ~kinds:
      [|
        Block_stubs.Attr "id";
        Block_stubs.Attr "tabindex";
        Block_stubs.Attr "aria-checked";
        Block_stubs.Click;
        Block_stubs.Node;
        Block_stubs.Text;
        Block_stubs.Node;
      |]

let group_template =
  Block_stubs.template ~markup:{|<div role="group"><div role="presentation"> </div><!----></div>|}
    ~walk:[| 0; 0; 2; 0; 3; 1 |] ~targets:[| 0; 0; 1; 1; 2; 3 |]
    ~kinds:
      [|
        Block_stubs.Class;
        Block_stubs.Attr "aria-labelledby";
        Block_stubs.Attr "id";
        Block_stubs.Class;
        Block_stubs.Text;
        Block_stubs.Node;
      |]

let menu_template =
  Block_stubs.template
    ~markup:{|<div><div class="backdrop"></div><div role="menu" aria-label="Theme and code style"><!----><!----></div></div>|}
    ~walk:[| 0; 0; 3; 1; 4; 0; 7; 1 |] ~targets:[| 1; 2; 3; 4 |]
    ~kinds:[| Block_stubs.Click; Block_stubs.Class; Block_stubs.Node; Block_stubs.Node |]

let make_props () = ((), ())

let make =
  Block_stubs.component
    ~markup:
      {|<div><button id="theme-button" type="button" aria-label="Theme" aria-haspopup="menu"><svg class="icon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="6.25" fill="none" stroke="currentColor" stroke-width="1.5"></circle><path d="M8 1.75 A6.25 6.25 0 0 1 8 14.25 Z" fill="currentColor"></path></svg><span class="topbar-label">Theme</span></button><!----></div>|}
    ~walk:[| 0; 0; 3; 1 |] ~targets:[| 0; 1; 1; 1; 2 |]
    ~kinds:[| Block_stubs.Class; Block_stubs.Class; Block_stubs.Attr "aria-expanded"; Block_stubs.Click; Block_stubs.Node |]
    (fun ((), ()) ->
      let opened = State.make false in
      let current = State.make Theme.Dark in
      let code = State.make None in
      let active = State.make 0 in
      let close ~refocus =
        State.set opened false;
        if refocus then Yuka.Browser.focus "theme-button"
      in
      let open_menu () =
        let theme = Theme.current () in
        State.set current theme;
        State.set code (Theme.current_code ());
        State.set active (index_of (Ui theme));
        State.set opened true;
        Yuka.Browser.focus (item_id (Ui theme))
      in
      let move step =
        let count = List.length choices in
        let next = (State.peek active + step + count) mod count in
        State.set active next;
        Yuka.Browser.focus (item_id (List.nth choices next))
      in
      let choose choice =
        (match choice with
        | Ui theme ->
            Theme.apply theme;
            State.set current theme
        | Code choice ->
            Theme.apply_code choice;
            State.set code choice);
        close ~refocus:true
      in
      Yuka.Effect.after (fun () ->
          Yuka.Browser.on_window "keydown" (fun event ->
              if State.peek opened then
                match Yuka.Event.key event with
                | "Escape" -> close ~refocus:true
                | "Tab" -> close ~refocus:false
                | "ArrowDown" ->
                    Yuka.Event.prevent_default event;
                    move 1
                | "ArrowUp" ->
                    Yuka.Event.prevent_default event;
                    move (-1)
                | "Home" ->
                    Yuka.Event.prevent_default event;
                    move (-State.peek active)
                | "End" ->
                    Yuka.Event.prevent_default event;
                    move (List.length choices - 1 - State.peek active)
                | _ -> ()));
      let item choice =
        let checked =
          match choice with Ui theme -> State.get current = theme | Code choice -> State.get code = choice
        in
        Block_stubs.block item_template
          [|
            Block.attr (item_id choice);
            Block.attr (if State.get active = index_of choice then "0" else "-1");
            Block_stubs.bool_attr checked;
            Block.on_click (fun _ -> choose choice);
            Block_stubs.node
              (match choice with
              | Ui theme -> Block_stubs.block swatch_theme [| Block.class_name Css.swatch; Block.attr (Theme.slug theme) |]
              | Code None ->
                  Block_stubs.block swatch_auto
                    [| Block.class_name Css.swatch; Block.attr (Theme.slug (State.get current)) |]
              | Code (Some code) ->
                  Block_stubs.block swatch_code
                    [| Block.class_name (Css.swatch ^ " " ^ Css.code_swatch); Block.attr (Theme.Code.slug code) |]);
            Block.text
              (match choice with
              | Ui theme -> Theme.label theme
              | Code None -> "Auto"
              | Code (Some code) -> Theme.Code.label code);
            Block_stubs.node (if checked then Block_stubs.block check [| Block.attr Css.check |] else Block_stubs.empty);
          |]
      in
      let group ~id ~label items =
        Block_stubs.block group_template
          [|
            Block.class_name Css.group;
            Block.attr id;
            Block.attr id;
            Block.class_name Css.heading;
            Block.text label;
            Block_stubs.node (Block_stubs.many (List.map item items));
          |]
      in
      let view () =
        [|
          Block.class_name Css.theme;
          Block.class_name ("topbar-link " ^ Css.button);
          Block_stubs.bool_attr (State.get opened);
          Block.on_click (fun _ -> if State.peek opened then close ~refocus:false else open_menu ());
          Block_stubs.node
            (if State.get opened then
               Block_stubs.block menu_template
                 [|
                   Block.on_click (fun _ -> close ~refocus:false);
                   Block.class_name ("menu " ^ Css.menu);
                   Block_stubs.node (group ~id:"theme-group" ~label:"Theme" theme_choices);
                   Block_stubs.node (group ~id:"code-group" ~label:"Code" code_choices);
                 |]
             else Block_stubs.empty);
        |]
      in
      fun ((), ()) -> view ())
