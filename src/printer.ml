module Buffer = Stdlib.Buffer

open Types
open Base

  let escape = Template_build.escape

  let put b s start i entity =
    Buffer.add_substring b s start (i - start);
    Buffer.add_string b entity;
    i + 1

  let add_escaped b ~quote s =
    let n = String.length s in
    let start = ref 0 and i = ref (Web.skip_clean s 0) in
    while !i < n do
      (match String.unsafe_get s !i with
      | '&' -> start := put b s !start !i "&amp;"
      | '<' -> start := put b s !start !i "&lt;"
      | '>' when not quote -> start := put b s !start !i "&gt;"
      | '"' when quote -> start := put b s !start !i "&quot;"
      | _ -> ());
      i := Web.skip_clean s (!i + 1)
    done;
    Buffer.add_substring b s !start (n - !start)

  let blocked_logged = ref false

  let log_blocked name value =
    if not !blocked_logged then begin
      blocked_logged := true;
      log_message `Warn ("printed " ^ Url.blocked ^ " for an unsafe URL in " ^ name ^ ": " ^ String.escaped value)
    end

  let add_attr b ?(literal = false) ~tag name value =
    if not (Url.valid_name name) then invalid_arg ("Yuka: refused attribute name " ^ String.escaped name);
    let tag = Web.lowercase tag and lname = Web.lowercase name in
    let value = if literal && Url.html_sink ~tag lname then value else Url.check ~tag ~log:log_blocked lname value in
    Buffer.add_char b ' ';
    Buffer.add_string b name;
    Buffer.add_string b "=\"";
    add_escaped b ~quote:true value;
    Buffer.add_char b '"'

  let open_tag b tag =
    if not (Url.valid_tag tag) then invalid_arg ("Yuka: refused tag name " ^ String.escaped tag);
    Buffer.add_char b '<';
    Buffer.add_string b tag

  let javascript_type = function
    | None -> true
    | Some t -> (
        match String.lowercase_ascii (String.trim t) with
        | "" | "module" | "application/ecmascript" | "application/javascript" | "application/x-ecmascript"
        | "application/x-javascript" | "text/ecmascript" | "text/javascript" | "text/javascript1.0"
        | "text/javascript1.1" | "text/javascript1.2" | "text/javascript1.3" | "text/javascript1.4"
        | "text/javascript1.5" | "text/jscript" | "text/livescript" | "text/x-ecmascript" | "text/x-javascript" ->
            true
        | _ -> false)

  let add_raw b ~tag ~type_ text =
    let n = String.length text in
    let at i part =
      let k = String.length part in
      i + k <= n && String.lowercase_ascii (String.sub text i k) = part
    in
    let data_block = tag = "script" && not (javascript_type type_) in
    let start = ref 0 in
    for i = 0 to n - 1 do
      if text.[i] = '<' then
        if data_block then begin
          Buffer.add_substring b text !start (i - !start);
          Buffer.add_string b "\\u003c";
          start := i + 1
        end
        else if at i "</" || (tag = "script" && at i "<!--") then begin
          Buffer.add_substring b text !start (i - !start);
          Buffer.add_string b "<\\";
          start := i + 1
        end
    done;
    Buffer.add_substring b text !start (n - !start)

  let raw_text_children tag children =
    let refuse () =
      invalid_arg ("Yuka: <" ^ tag ^ "> takes one text or one hole that gives a text")
    in
    match children with
    | [] -> ""
    | [ Text t ] -> t
    | [ Hole f ] -> ( match f () with Text t -> t | Fragment [] -> "" | _ -> refuse ())
    | _ -> refuse ()

  let fill_script =
    "<script>window.__yukaFill=function(id){var t=document.querySelector('template[data-yuka-fill=\"'+id+'\"]'),w=document.createTreeWalker(document,128),c;while(c=w.nextNode())if(c.data==='['+id)break;if(!t||!c)return;var d=1,n=c.nextSibling,x;while(n){if(n.nodeType===8){if(n.data.charAt(0)==='[')d++;else if(n.data===']'&&--d===0)break}x=n.nextSibling;n.parentNode.removeChild(n);n=x}n.parentNode.insertBefore(t.content,n);t.remove();if(document.currentScript)document.currentScript.remove()};</script>"

  let session ~streaming ~islands_only =
    { streaming; islands_only; islands = 0; asyncs = 0; awaits = 0; pending = []; preload = None;
      preloaded = []; depth = 0; queued = []; id_prefix = ""; entry = None;
      current = None; in_fill = false; answers = []; answered = []; select_value = None; form = None;
      csrf = None; sheets = []; held = []; context = None; shared = []; contexts = 0;
      id_scope = "p-"; id_count = 0; page_scope = "p-"; page_count = 0;
      invalid = []; invalid_focused = false }

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

  let context_script id name json =
    "<script type=\"application/json\" data-yuka-context=\"" ^ escape ~quote:true id ^ "\" data-name=\""
    ^ escape ~quote:true name ^ "\">" ^ Json.to_string json ^ "</script>"

  let coded_scope env =
    let rec go acc = function
      | Scheduler.Bound ((Coded { name; _ } as b), e) ->
          go (if List.exists (fun (n, _) -> String.equal n name) acc then acc else (name, b) :: acc) e
      | Scheduler.Bound (_, e) | Scheduler.Island e -> go acc e
      | Scheduler.Empty | Scheduler.Root _ -> List.rev acc
    in
    go [] env

  let context_ids s env =
    List.map
      (fun (name, b) ->
        match List.assq_opt b s.shared with
        | Some id -> (name, id, "")
        | None ->
            let id =
              if String.equal name route_name then "route"
              else begin
                s.contexts <- s.contexts + 1;
                s.id_prefix ^ "c" ^ string_of_int s.contexts
              end
            in
            s.shared <- (b, id) :: s.shared;
            let json = match b with Coded { json; _ } -> json () | _ -> `Null in
            (name, id, context_script id name json))
      (coded_scope env)

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

  let needs_special tag =
    match Web.lowercase tag with "select" | "textarea" | "option" | "a" -> true | _ -> false

  type namespace = Html | Svg | Math | Select

  let enter ns tag =
    match (ns, tag) with Html, "svg" -> Svg | Html, "math" -> Math | Html, "select" -> Select | Svg, "foreignobject" -> Html | ns, _ -> ns

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
      | Fixed_element { tag; attrs; children } as e -> (
          if not (Url.valid_tag tag) then invalid_arg ("Yuka: refused tag name " ^ String.escaped tag);
          match String.lowercase_ascii tag with
          | "script" | "style" -> emit (Subtree e)
          | ("svg" | "math" | "foreignobject") as lt -> go_element ~only tag attrs children ~context:(Some lt)
          | "a" -> go_element ~only tag attrs children ~context:None
          | _ when needs_special tag -> emit (Subtree e)
          | _ -> go_element ~only tag attrs children ~context:None)
    and go_element ~only:_ tag attrs children ~context =
      let fixed = List.filter_map (function Fixed (n, v) -> Some (n, v) | Part_attr _ -> None) attrs in
      if (not (needs_special tag))
         && List.length fixed = List.length attrs
         && not (Web.lowercase tag = "input" && List.mem_assoc "name" fixed)
      then begin
        Buffer.add_char raw '<';
        Buffer.add_string raw tag;
        List.iter (fun (n, v) -> add_attr raw ~literal:true ~tag n v) fixed;
        Buffer.add_char raw '>'
      end
      else emit (Open (tag, attrs));
      if not (Template_build.is_void (String.lowercase_ascii tag)) then begin
        Option.iter (fun lt -> emit (Enter lt)) context;
        (match children with [ c ] -> go ~only:true c | cs -> List.iter (go ~only:false) cs);
        if context <> None then emit Leave;
        Buffer.add_string raw "</";
        Buffer.add_string raw tag;
        Buffer.add_char raw '>'
      end
    in
    go ~only:false shape;
    flush ();
    Array.of_list (List.rev !ops)

  let ops (t : template) =
    if Array.length t.ops = 0 then t.ops <- compile (Template.shape t);
    t.ops

  let kept_buffer = 1_048_576
  let rendering = Web.local (fun () -> Atomic.make 0)

  let rec print ?env s build =
    let owner = new_owner () in
    Option.iter (fun e -> owner.env <- e) env;
    let scoped e f =
      let old = owner.env in
      owner.env <- e;
      match f () with
      | r ->
          owner.env <- old;
          r
      | exception x ->
          owner.env <- old;
          raise x
    in
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
    let foreign = ref [] in
    let namespace () = match !foreign with ns :: _ -> ns | [] -> Html in
    let marker m =
      if hydrating () then Buffer.add_string b m;
      after_text := false
    in
    let field_attrs ~tag each add =
      let field =
        match (s.invalid, Web.lowercase tag) with
        | [], _ -> None
        | invalid, ("input" | "select" | "textarea") ->
            let name = ref None and hidden = ref false in
            each (fun _ n v ->
                if n = "name" && Option.is_none !name then name := Some v
                else if n = "type" && Web.lowercase v = "hidden" then hidden := true);
            Option.map (fun id -> (id, !hidden)) (Option.bind !name (fun n -> List.assoc_opt n invalid))
        | _ -> None
      in
      match field with
      | None -> each add
      | Some (id, hidden) ->
          let described = ref false and focused = ref false in
          each (fun literal n v ->
              match Web.lowercase n with
              | "aria-invalid" -> ()
              | "aria-describedby" ->
                  described := true;
                  add literal n (v ^ " " ^ id)
              | "autofocus" ->
                  focused := true;
                  add literal n v
              | _ -> add literal n v);
          add false "aria-invalid" "true";
          if not !described then add false "aria-describedby" id;
          if not (hidden || s.invalid_focused) then begin
            if not !focused then add false "autofocus" "";
            s.invalid_focused <- true
          end
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
          let ids = next_id () ^ "-" in
          let in_ids f =
            let scope = s.id_scope and count = s.id_count in
            let restore () =
              s.id_scope <- scope;
              s.id_count <- count
            in
            s.id_scope <- ids;
            s.id_count <- 0;
            match f () with
            | r ->
                restore ();
                r
            | exception e ->
                restore ();
                raise e
          in
          let body () =
            match Async.status async with
            | Async.Done v -> render v
            | Async.Failed m -> failed (shown "await" m)
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
              let id = s.id_prefix ^ "s" ^ string_of_int s.awaits and env = owner.env in
              s.pending <-
                Pending_await
                  {
                    id;
                    subscribe =
                      (fun cb -> Async.on_settled async (fun _ -> cb ()));
                    fill = (fun () -> held (fun () -> in_ids (fun () -> print ~env s body)));
                    fill_failed =
                      (fun m -> held (fun () -> in_ids (fun () -> print ~env s (fun () -> failed m))));
                    inside_island = inside;
                  }
                :: s.pending;
              let start = Buffer.length b and outer_held = s.held in
              s.held <- [];
              incr holding;
              Buffer.add_string b ("<!--[" ^ id ^ "-->");
              after_text := false;
              (match in_ids (fun () -> go loading) with
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
              in_ids (fun () -> go (body ()));
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
                  (match s.current with
                  | Some path when needs_special tag && not (hydrating ()) ->
                      let href = ref None and current = ref false in
                      let add n v =
                        if n = "href" then (if Option.is_none !href then href := Some v)
                        else if n = "aria-current" then current := true;
                        add_attr b ~tag n v
                      in
                      List.iter
                        (function
                          | Fixed (n, v) -> add n v
                          | Part_attr i -> (
                              match parts.(i) with
                              | Attribute (Static (n, v)) -> add n v
                              | Attribute (Dynamic (n, f)) -> Option.iter (add n) (f ())
                              | Attribute (Handler _) | Child _ | No_attribute -> ()))
                        attrs;
                      (match !href with
                      | Some h when String.equal h path && not !current -> add_attr b ~tag "aria-current" "page"
                      | _ -> ())
                  | _ ->
                      let each add =
                        List.iter
                          (function
                            | Fixed (n, v) -> add true n v
                            | Part_attr i -> (
                                match parts.(i) with
                                | Attribute (Static (n, v)) -> add false n v
                                | Attribute (Dynamic (n, f)) -> Option.iter (add false n) (f ())
                                | Attribute (Handler _) | Child _ | No_attribute -> ()))
                          attrs
                      in
                      field_attrs ~tag each (fun literal n v -> add_attr b ~literal ~tag n v));
                  Buffer.add_char b '>';
                  after_text := false
              | Subtree shape -> go (Template.expand_shape parts shape)
              | Enter lt -> foreign := enter (namespace ()) lt :: !foreign
              | Leave -> foreign := List.tl !foreign)
            (ops template)
      | Catch { children; fallback; _ } -> (
          let length = Buffer.length b and text = !after_text and saved = snapshot s and context = !foreign in
          try
            marker "<!--[-->";
            go (children ());
            marker "<!--]-->"
          with e ->
            cut length;
            after_text := text;
            foreign := context;
            restore s saved;
            log_message `Error ("Yuka.Catch: " ^ Web.exn_to_string e);
            marker "<!--[!-->";
            go (fallback ~error:"server error" ~reset:ignore);
            marker "<!--]-->")
      | Provide { add; children; _ } ->
          marker "<!--[-->";
          scoped (add owner.env) (fun () -> go (children ()));
          marker "<!--]-->"
      | Slot { content; _ } ->
          let rec page = function
            | Scheduler.Empty | Scheduler.Root _ -> owner.env
            | Scheduler.Bound (_, e) -> page e
            | Scheduler.Island e -> e
          in
          let scope = s.id_scope and count = s.id_count in
          s.id_scope <- s.page_scope;
          s.id_count <- s.page_count;
          marker "<!--[$-->";
          scoped (page owner.env) (fun () -> Option.iter go content);
          marker "<!--]-->";
          s.page_count <- s.id_count;
          s.id_scope <- scope;
          s.id_count <- count
      | Island { name; props; render; start = strategy } ->
          s.islands <- s.islands + 1;
          let id = s.id_prefix ^ "i" ^ string_of_int s.islands in
          let direct = s.depth = 0 && not s.in_fill in
          (match s.entry with
          | Some tag ->
              s.entry <- None;
              if direct then Buffer.add_string b tag else s.queued <- tag :: s.queued
          | None -> ());
          (match (strategy, s.preload) with
          | `Lazy _, _ | _, None -> ()
          | _, Some f ->
              List.iter
                (fun url ->
                  if not (List.mem url s.preloaded) then begin
                    s.preloaded <- url :: s.preloaded;
                    let link = "<link rel=\"modulepreload\" href=\"" ^ escape ~quote:true url ^ "\">" in
                    if direct then Buffer.add_string b link else s.queued <- link :: s.queued
                  end)
                (f name));
          let scope = context_ids s owner.env in
          let outermost = s.depth = 0 and start = Buffer.length b in
          Buffer.add_string b
            ("<yuka-island data-name=\"" ^ escape ~quote:true name
           ^ "\" data-id=\"" ^ id ^ "\" style=\"display:contents\""
           ^ (match strategy with
               | `Load -> ""
               | `Idle | `Lazy `Idle -> " data-start=\"idle\""
               | `Visible | `Lazy `Visible -> " data-start=\"visible\""
               | `Interaction | `Lazy `Interaction ->
                   " data-start=\"interaction\"")
           ^ (match scope with
               | [] -> ""
               | l -> " data-ctx=\"" ^ escape ~quote:true (String.concat " " (List.map (fun (n, i, _) -> n ^ "=" ^ i) l)) ^ "\"")
           ^ ">");
          after_text := false;
          let saved = snapshot s in
          s.depth <- s.depth + 1;
          s.answers <- [];
          s.page_scope <- s.id_scope;
          s.page_count <- s.id_count;
          s.id_scope <- id ^ "-";
          s.id_count <- 0;
          let mine =
            match scoped (Scheduler.Island owner.env) (fun () -> go (render ())) with
            | () ->
                s.depth <- s.depth - 1;
                s.id_scope <- s.page_scope;
                s.id_count <- s.page_count;
                s.page_scope <- saved.page_scope;
                s.page_count <- saved.page_count;
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
          List.iter (fun (_, _, script) -> Buffer.add_string b script) scope;
          Buffer.add_string b
            ("<script type=\"application/json\" data-yuka-props=\"" ^ id ^ "\">"
            ^ Json.to_string props ^ "</script>");
          if s.depth = 0 && not s.in_fill then begin
            List.iter (Buffer.add_string b) (List.rev s.queued);
            s.queued <- []
          end;
          after_text := false
      | Each { items; key; equal = _; render } ->
          marker "<!--[-->";
          rows items key render;
          marker "<!--]-->"
      | Element { tag; attrs; children }
        when (match String.lowercase_ascii tag with "script" | "style" -> true | _ -> false) ->
          let lt = String.lowercase_ascii tag in
          let text = raw_text_children lt children in
          let type_ =
            List.find_map
              (function
                | Static (n, v) when String.lowercase_ascii n = "type" -> Some (Some v)
                | Dynamic (n, f) when String.lowercase_ascii n = "type" -> Some (f ())
                | _ -> None)
              attrs
          in
          open_tag b tag;
          List.iter
            (function
              | Static (name, v) -> add_attr b ~tag name v
              | Dynamic (name, f) -> Option.iter (add_attr b ~tag name) (f ())
              | Handler _ -> ())
            attrs;
          Buffer.add_char b '>';
          if namespace () = Html then add_raw b ~tag:lt ~type_:(Option.join type_) text
          else add_escaped b ~quote:false text;
          Buffer.add_string b "</";
          Buffer.add_string b tag;
          Buffer.add_char b '>';
          after_text := false
      | Element { tag; attrs; children } ->
          open_tag b tag;
          let value =
            if needs_special tag then special tag attrs
            else begin
                field_attrs ~tag
                  (fun add ->
                    List.iter
                      (function
                        | Static (name, v) -> add false name v
                        | Dynamic (name, f) -> Option.iter (add false name) (f ())
                        | Handler _ -> ())
                      attrs)
                  (fun _ name v -> add_attr b ~tag name v);
                None
            end
          in
          let outer = s.invalid in
          (match s.form with
          | Some (action, key, _, errors)
            when Web.lowercase tag = "form"
                 && List.exists (function Static ("data-yuka-action", a) -> a = action | _ -> false) attrs
                 && List.exists (function Static ("data-yuka-key", k) -> k = key | _ -> false) attrs ->
              s.invalid <-
                List.filter_map
                  (function Some field, _ -> Some (field, error_id ~action ~key field) | None, _ -> None)
                  errors
          | _ -> ());
          Buffer.add_char b '>';
          after_text := false;
          let lt = String.lowercase_ascii tag in
          if not (Template_build.is_void lt) then begin
            (match (lt, value) with
            | "textarea", Some v ->
                if String.length v > 0 && v.[0] = '\n' then
                  Buffer.add_char b '\n';
                add_escaped b ~quote:false v
            | "select", _ ->
                let outer = s.select_value in
                s.select_value <- value;
                foreign := enter (namespace ()) lt :: !foreign;
                (match contents children with
                | () -> foreign := List.tl !foreign
                | exception e ->
                    foreign := List.tl !foreign;
                    raise e);
                s.select_value <- outer
            | ("svg" | "math" | "foreignobject"), _ ->
                foreign := enter (namespace ()) lt :: !foreign;
                (match contents children with
                | () -> foreign := List.tl !foreign
                | exception e ->
                    foreign := List.tl !foreign;
                    raise e)
            | _ -> contents children);
            Buffer.add_string b "</";
            Buffer.add_string b tag;
            Buffer.add_char b '>';
            after_text := false
          end;
          s.invalid <- outer
    and special tag attrs =
      let lt = String.lowercase_ascii tag in
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
        if lt = "select" || lt = "textarea" then List.filter (fun (name, _) -> name <> "value") resolved
        else if lt = "option" && value <> None && s.select_value = value && not (List.mem_assoc "selected" resolved)
        then resolved @ [ ("selected", "") ]
        else resolved
      in
      let resolved =
        match (lt, s.current) with
        | "a", Some path
          when (not (hydrating ()))
               && (match List.assoc_opt "href" resolved with
                  | Some href -> String.equal href path
                  | None -> false)
               && not (List.mem_assoc "aria-current" resolved) ->
            resolved @ [ ("aria-current", "page") ]
        | _ -> resolved
      in
      field_attrs ~tag (fun add -> List.iter (fun (name, v) -> add false name v) resolved) (fun _ name v ->
          add_attr b ~tag name v);
      value
    and contents = function
      | [ Hole f ] -> go (f ())
      | [ Each { items; key; equal = _; render } ] -> rows items key render
      | children -> List.iter go children
    and rows : type a. (unit -> a array) -> (a -> string) -> (a -> node) -> unit =
     fun items key render ->
      let seen = Hashtbl.create 8 in
      Array.iter
        (fun item ->
          let k = key item in
          if not (Hashtbl.mem seen k) then begin
            Hashtbl.add seen k ();
            let n = unwrap (render item) in
            if Template.single_element n then go n
            else begin
              marker "<!--[-->";
              go n;
              marker "<!--]-->"
            end
          end)
        (items ())
    in
    let server_rendering = server_rendering () and current_session = current_session () in
    let current_owner = current_owner () and listener = Scheduler.listener () in
    let rendering = Web.local_get rendering in
    let previous = !server_rendering in
    let previous_session = !current_session in
    let previous_listener = !listener in
    Atomic.incr rendering;
    server_rendering := true;
    Scheduler.seal ();
    current_session := Some s;
    let restore () =
      let others = Atomic.fetch_and_add rendering (-1) > 1 in
      server_rendering := others && previous;
      current_session := if others then previous_session else None
    in
    let owned () = match !current_owner with Some o -> o == owner | None -> false in
    let kept () =
      !server_rendering
      && !listener == previous_listener
      && match !current_session with Some c -> c == s | None -> false
    in
    let overlap () =
      server_rendering := Atomic.fetch_and_add rendering (-1) > 1;
      current_session := None;
      listener := None;
      current_owner := None;
      dispose_owner owner;
      release ();
      failwith
        "Yuka.Server: two server renders overlapped: while this render was suspended, another render on the same system thread, for example in another fiber, changed the state that they share. Do not suspend a fiber during a server render."
    in
    (match with_owner owner (fun () -> go (build ()); owned ()) with
    | true when kept () ->
        restore ();
        dispose_owner owner
    | _ -> overlap ()
    | exception e when kept () ->
        restore ();
        dispose_owner owner;
        release ();
        raise e
    | exception _ -> overlap ());
    if s.held <> [] then begin
      s.queued <- s.held @ s.queued;
      s.held <- []
    end;
    let html = Buffer.contents b in
    release ();
    html

  let seek ~outlet node =
    let o = Option.get !(current_owner ()) in
    let rec find = function
      | Element { tag = "yuka-outlet"; attrs = Static ("data-k", k) :: _; children } when String.equal k outlet ->
          Some (Fragment children)
      | Element { children; _ } | Fragment children -> first children
      | Hole f -> find (f ())
      | Catch { children; _ } -> find (children ())
      | Await { async; render; _ } -> ( match Async.status async with Async.Done v -> find (render v) | _ -> None)
      | Template { parts; _ } ->
          first (Array.fold_right (fun p acc -> match p with Child n -> n :: acc | _ -> acc) parts [])
      | Provide { add; children; _ } -> (
          let e = o.env in
          o.env <- add e;
          match find (children ()) with
          | None ->
              o.env <- e;
              None
          | r -> r)
      | Text _ | Island _ | Each _ | Slot _ -> None
    and first = function
      | [] -> None
      | c :: cs -> ( match find c with None -> first cs | r -> r)
    in
    find node

  let render_html build = print (session ~streaming:false ~islands_only:false) build

  let to_html root = render_html (fun () -> root)
