open Types
open Base

  let escape = Template_build.escape

  let add_escaped = Template_build.add_escaped

  let add_attr b name value =
    Buffer.add_char b ' ';
    Buffer.add_string b name;
    Buffer.add_string b "=\"";
    add_escaped b ~quote:true value;
    Buffer.add_char b '"'

  let fill_script =
    "<script>window.__yukaFill=function(id){var t=document.querySelector('template[data-yuka-fill=\"'+id+'\"]'),w=document.createTreeWalker(document,128),c;while(c=w.nextNode())if(c.data==='['+id)break;if(!t||!c)return;var d=1,n=c.nextSibling,x;while(n){if(n.nodeType===8){if(n.data.charAt(0)==='[')d++;else if(n.data===']'&&--d===0)break}x=n.nextSibling;n.parentNode.removeChild(n);n=x}n.parentNode.insertBefore(t.content,n);t.remove();if(document.currentScript)document.currentScript.remove()};</script>"

  let session ~streaming ~islands_only =
    { streaming; islands_only; islands = 0; asyncs = 0; awaits = 0; pending = []; preload = None;
      preloaded = []; depth = 0; queued = []; id_prefix = ""; entry = None;
      current = None; in_fill = false; answers = []; answered = []; select_value = None; form = None;
      csrf = None; sheets = []; held = [] }

  let answer_script key json =
    "<script type=\"application/json\" data-yuka-answer=\"" ^ escape ~quote:true key ^ "\">"
    ^ Json.to_string json ^ "</script>"

  let pending_answer_script key =
    "<script type=\"application/json\" data-yuka-answer=\"" ^ escape ~quote:true key
    ^ "\" data-pending></script>"

  let answers_html answers =
    String.concat ""
      (List.rev_map
         (function key, Some json -> answer_script key json | key, None -> pending_answer_script key)
         answers)

  let take_answers s =
    let html = answers_html s.answers in
    s.answers <- [];
    html

  let take_pending s =
    let p = List.rev s.pending in
    s.pending <- [];
    p

  let sheet_link href =
    "<link rel=\"stylesheet\" href=\"" ^ escape ~quote:true href ^ "\" data-yuka-css>"

  let sheet_of = function
    | Fragment
        [ Element { tag = "link"; attrs = [ _; Static ("href", href); Static ("data-yuka-css", _) ]; _ }; body ] ->
        Some (href, body)
    | _ -> None

  let take_held s =
    let l = String.concat "" (List.rev s.held) in
    s.held <- [];
    l

  let take_links s =
    let l = String.concat "" (List.rev s.queued) in
    s.queued <- [];
    l

  let needs_special = function "select" | "textarea" | "option" | "a" -> true | _ -> false

  let compile shape =
    let ops = ref [] and raw = Buffer.create 64 in
    let flush () =
      if Buffer.length raw > 0 then begin
        ops := Raw (Buffer.contents raw) :: !ops;
        Buffer.clear raw
      end
    in
    let emit op =
      flush ();
      ops := op :: !ops
    in
    let rec go ~only = function
      | Fixed_text "" -> ()
      | Fixed_text t -> emit (Static_text (escape ~quote:false t))
      | Part i -> emit (if only then Only_part i else Child_part i)
      | Fixed_element { tag; _ } as e when needs_special tag && tag <> "a" -> emit (Subtree e)
      | Fixed_element { tag; attrs; children } ->
          let fixed = List.filter_map (function Fixed (n, v) -> Some (n, v) | Part_attr _ -> None) attrs in
          if (not (needs_special tag)) && List.length fixed = List.length attrs then begin
            Buffer.add_char raw '<';
            Buffer.add_string raw tag;
            List.iter (fun (n, v) -> add_attr raw n v) fixed;
            Buffer.add_char raw '>'
          end
          else emit (Open (tag, attrs));
          if not (Template_build.is_void tag) then begin
            (match children with [ c ] -> go ~only:true c | cs -> List.iter (go ~only:false) cs);
            Buffer.add_string raw "</";
            Buffer.add_string raw tag;
            Buffer.add_char raw '>'
          end
    in
    go ~only:false shape;
    flush ();
    Array.of_list (List.rev !ops)

  let ops (t : template) =
    if Array.length t.ops = 0 then t.ops <- compile t.shape;
    t.ops

  let kept_buffer = 262_144

  let rec print s build =
    let b = match Web.take_buffer () with Some b -> b | None -> Buffer.create 4096 in
    let peak = ref 0 in
    let cut n =
      peak := max !peak (Buffer.length b);
      Buffer.truncate b n
    in
    let release () =
      if max !peak (Buffer.length b) <= kept_buffer then begin
        Buffer.clear b;
        Web.give_buffer b
      end
    in
    let after_text = ref false in
    let hydrating () = (not s.islands_only) || s.depth > 0 in
    let marker m =
      if hydrating () then Buffer.add_string b m;
      after_text := false
    in
    let holding = ref 0 in
    let use_sheet href =
      if s.islands_only && not (List.mem href s.sheets) then begin
        s.sheets <- href :: s.sheets;
        if hydrating () || !holding > 0 then s.held <- sheet_link href :: s.held
        else Buffer.add_string b (sheet_link href)
      end
    in
    let rec unwrap n =
      match sheet_of n with
      | Some (href, body) ->
          use_sheet href;
          unwrap body
      | None -> n
    in
    let rec go n =
      match unwrap n with
      | Text "" -> ()
      | Text t ->
          if !after_text && hydrating () then Buffer.add_string b "<!---->";
          add_escaped b ~quote:false t;
          after_text := true
      | Fragment children -> List.iter go children
      | Hole f ->
          marker "<!--[-->";
          go (f ());
          marker "<!--]-->"
      | Await { async; loading; failed; render } -> (
          let body () =
            match Async.status async with
            | Async.Done v -> render v
            | Async.Failed m -> failed m
            | Async.Pending -> loading
          in
          match Async.status async with
          | Async.Pending when s.streaming ->
              let inside = s.depth > 0 in
              let held f =
                let outer = s.depth and outer_fill = s.in_fill in
                s.depth <- (if inside then max outer 1 else outer);
                s.in_fill <- true;
                let restore () =
                  s.depth <- outer;
                  s.in_fill <- outer_fill
                in
                match f () with
                | r ->
                    restore ();
                    r
                | exception e ->
                    restore ();
                    raise e
              in
              s.awaits <- s.awaits + 1;
              let id = s.id_prefix ^ "s" ^ string_of_int s.awaits in
              s.pending <-
                Pending_await
                  {
                    id;
                    subscribe =
                      (fun cb -> Async.on_settled async (fun _ -> cb ()));
                    fill = (fun () -> held (fun () -> print s body));
                    fill_failed =
                      (fun m -> held (fun () -> print s (fun () -> failed m)));
                    inside_island = inside;
                  }
                :: s.pending;
              let start = Buffer.length b and outer_held = s.held in
              s.held <- [];
              incr holding;
              Buffer.add_string b ("<!--[" ^ id ^ "-->");
              after_text := false;
              (match go loading with
              | () -> decr holding
              | exception e ->
                  decr holding;
                  s.held <- outer_held;
                  raise e);
              Buffer.add_string b "<!--]-->";
              after_text := false;
              let mine = s.held in
              s.held <- outer_held;
              if mine <> [] then
                if hydrating () || !holding > 0 then s.held <- mine @ outer_held
                else begin
                  let region = Buffer.sub b start (Buffer.length b - start) in
                  cut start;
                  Buffer.add_string b (String.concat "" (List.rev mine));
                  Buffer.add_string b region
                end
          | _ ->
              marker "<!--[-->";
              go (body ());
              marker "<!--]-->")
      | Template { template; parts } ->
          Array.iter
            (function
              | Raw r ->
                  Buffer.add_string b r;
                  after_text := false
              | Static_text t ->
                  if !after_text && hydrating () then Buffer.add_string b "<!---->";
                  Buffer.add_string b t;
                  after_text := true
              | Child_part i -> ( match parts.(i) with Child n -> go n | Attribute _ | No_attribute -> ())
              | Only_part i -> ( match parts.(i) with Child n -> contents [ n ] | Attribute _ | No_attribute -> ())
              | Open (tag, attrs) ->
                  Buffer.add_char b '<';
                  Buffer.add_string b tag;
                  (if needs_special tag then ignore (special tag (Template.expand_attrs parts attrs))
                   else
                     List.iter
                       (function
                         | Fixed (n, v) -> add_attr b n v
                         | Part_attr i -> (
                             match parts.(i) with
                             | Attribute (Static (n, v)) -> add_attr b n v
                             | Attribute (Dynamic (n, f)) -> Option.iter (add_attr b n) (f ())
                             | Attribute (Handler _) | Child _ | No_attribute -> ()))
                       attrs);
                  Buffer.add_char b '>';
                  after_text := false
              | Subtree shape -> go (Template.expand_shape parts shape))
            (ops template)
      | Catch { children; fallback; _ } -> (
          let length = Buffer.length b and text = !after_text and saved = snapshot s in
          try
            marker "<!--[-->";
            go (children ());
            marker "<!--]-->"
          with e ->
            cut length;
            after_text := text;
            restore s saved;
            !log_error ("Yuka.Catch: " ^ Web.exn_to_string e);
            marker "<!--[!-->";
            go (fallback ~error:"server error" ~reset:ignore);
            marker "<!--]-->")
      | Slot { content; _ } ->
          marker "<!--[$-->";
          Option.iter go content;
          marker "<!--]-->"
      | Island { name; props; render; loading } ->
          s.islands <- s.islands + 1;
          let id = s.id_prefix ^ "i" ^ string_of_int s.islands in
          let direct = s.depth = 0 && not s.in_fill in
          (match s.entry with
          | Some tag ->
              s.entry <- None;
              if direct then Buffer.add_string b tag else s.queued <- tag :: s.queued
          | None -> ());
          let link =
            match (loading, s.preload) with
            | `Lazy _, _ | _, None -> None
            | _, Some f ->
                if List.mem name s.preloaded then None
                else begin
                  s.preloaded <- name :: s.preloaded;
                  Option.map
                    (fun url ->
                      "<link rel=\"modulepreload\" href=\""
                      ^ escape ~quote:true url ^ "\">")
                    (f name)
                end
          in
          (match link with
          | Some l when direct -> Buffer.add_string b l
          | Some l -> s.queued <- l :: s.queued
          | None -> ());
          let outermost = s.depth = 0 and start = Buffer.length b in
          Buffer.add_string b
            ("<yuka-island data-name=\"" ^ escape ~quote:true name
           ^ "\" data-id=\"" ^ id ^ "\" style=\"display:contents\""
           ^ (match loading with
               | `Load -> ""
               | `Idle | `Lazy `Idle -> " data-start=\"idle\""
               | `Visible | `Lazy `Visible -> " data-start=\"visible\""
               | `Interaction | `Lazy `Interaction ->
                   " data-start=\"interaction\"")
           ^ ">");
          after_text := false;
          let saved = snapshot s in
          s.depth <- s.depth + 1;
          s.answers <- [];
          let mine =
            match go (render ()) with
            | () ->
                s.depth <- s.depth - 1;
                let mine = s.answers in
                s.answers <- saved.answers;
                mine
            | exception e ->
                restore s saved;
                raise e
          in
          Buffer.add_string b "</yuka-island>";
          if outermost && s.held <> [] then begin
            let island = Buffer.sub b start (Buffer.length b - start) in
            cut start;
            Buffer.add_string b (take_held s);
            Buffer.add_string b island
          end;
          Buffer.add_string b (answers_html mine);
          Buffer.add_string b
            ("<script type=\"application/json\" data-yuka-props=\"" ^ id ^ "\">"
            ^ Json.to_string props ^ "</script>");
          if s.depth = 0 && not s.in_fill then begin
            List.iter (Buffer.add_string b) (List.rev s.queued);
            s.queued <- []
          end;
          after_text := false
      | Each { items; key = _; equal = _; render } ->
          marker "<!--[-->";
          rows items render;
          marker "<!--]-->"
      | Element { tag; attrs; children } ->
          Buffer.add_char b '<';
          Buffer.add_string b tag;
          let value =
            if needs_special tag then special tag attrs
            else begin
                List.iter
                  (function
                    | Static (name, v) -> add_attr b name v
                    | Dynamic (name, f) -> Option.iter (add_attr b name) (f ())
                    | Handler _ -> ())
                  attrs;
                None
            end
          in
          Buffer.add_char b '>';
          after_text := false;
          if not (Template_build.is_void tag) then begin
            (match (tag, value) with
            | "textarea", Some v ->
                if String.length v > 0 && v.[0] = '\n' then
                  Buffer.add_char b '\n';
                add_escaped b ~quote:false v
            | "select", _ ->
                let outer = s.select_value in
                s.select_value <- value;
                contents children;
                s.select_value <- outer
            | _ -> contents children);
            Buffer.add_string b "</";
            Buffer.add_string b tag;
            Buffer.add_char b '>';
            after_text := false
          end
    and special tag attrs =
      let resolved =
        List.filter_map
          (function
            | Static (name, value) -> Some (name, value)
            | Dynamic (name, f) -> Option.map (fun v -> (name, v)) (f ())
            | Handler _ -> None)
          attrs
      in
      let value = List.assoc_opt "value" resolved in
      let resolved =
        if tag = "select" || tag = "textarea" then List.filter (fun (name, _) -> name <> "value") resolved
        else if tag = "option" && value <> None && s.select_value = value && not (List.mem_assoc "selected" resolved)
        then resolved @ [ ("selected", "") ]
        else resolved
      in
      let resolved =
        match (tag, s.current) with
        | "a", Some path
          when (not (hydrating ()))
               && (match List.assoc_opt "href" resolved with
                  | Some href -> String.equal href path
                  | None -> false)
               && not (List.mem_assoc "aria-current" resolved) ->
            resolved @ [ ("aria-current", "page") ]
        | _ -> resolved
      in
      List.iter (fun (name, v) -> add_attr b name v) resolved;
      value
    and contents = function
      | [ Hole f ] -> go (f ())
      | [ Each { items; key = _; equal = _; render } ] -> rows items render
      | children -> List.iter go children
    and rows : type a. (unit -> a list) -> (a -> node) -> unit =
     fun items render ->
      List.iter
        (fun item ->
          let n = unwrap (render item) in
          if Template.single_element n then go n
          else begin
            marker "<!--[-->";
            go n;
            marker "<!--]-->"
          end)
        (items ())
    in
    let previous = !server_rendering in
    let previous_session = !current_session in
    server_rendering := true;
    current_session := Some s;
    let restore () =
      server_rendering := previous;
      current_session := previous_session
    in
    (match go (build ()) with
    | () -> restore ()
    | exception e ->
        restore ();
        release ();
        raise e);
    if s.held <> [] then begin
      s.queued <- s.held @ s.queued;
      s.held <- []
    end;
    let html = Buffer.contents b in
    release ();
    html

  let render_html build = print (session ~streaming:false ~islands_only:false) build

  let to_html root = render_html (fun () -> root)
