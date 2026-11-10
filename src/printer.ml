open Types
open Base

  let escape ~quote s =
    let b = Buffer.create (String.length s) in
    String.iter
      (function
        | '&' -> Buffer.add_string b "&amp;"
        | '<' -> Buffer.add_string b "&lt;"
        | '>' when not quote -> Buffer.add_string b "&gt;"
        | '"' when quote -> Buffer.add_string b "&quot;"
        | c -> Buffer.add_char b c)
      s;
    Buffer.contents b

  let void_tags =
    [ "area"; "base"; "br"; "col"; "embed"; "hr"; "img"; "input"; "link";
      "meta"; "source"; "track"; "wbr" ]

  let fill_script =
    "<script>window.__yukaFill=function(id){var t=document.querySelector('template[data-yuka-fill=\"'+id+'\"]'),w=document.createTreeWalker(document,128),c;while(c=w.nextNode())if(c.data==='['+id)break;if(!t||!c)return;var d=1,n=c.nextSibling,x;while(n){if(n.nodeType===8){if(n.data.charAt(0)==='[')d++;else if(n.data===']'&&--d===0)break}x=n.nextSibling;n.parentNode.removeChild(n);n=x}n.parentNode.insertBefore(t.content,n);t.remove();if(document.currentScript)document.currentScript.remove()};</script>"

  let skeleton_html root =
    let b = Buffer.create 256 in
    let after_text = ref false in
    let select_value = ref None in
    let marker m =
      Buffer.add_string b m;
      after_text := false
    in
    let rec go = function
      | Text "" -> ()
      | Text t ->
          if !after_text then Buffer.add_string b "<!---->";
          Buffer.add_string b (escape ~quote:false t);
          after_text := true
      | Fragment children -> List.iter go children
      | Template { node; _ } -> go node
      | Hole _ | Await _ | Each _ | Island _ -> marker "<!--[--><!--]-->"
      | Slot _ -> marker "<!--[$--><!--]-->"
      | Element { tag; attrs; children } ->
          let resolved =
            List.filter_map
              (function Static (name, value) -> Some (name, value) | _ -> None)
              attrs
          in
          let value = List.assoc_opt "value" resolved in
          let resolved =
            if tag = "select" || tag = "textarea" then
              List.filter (fun (name, _) -> name <> "value") resolved
            else if
              tag = "option" && value <> None && !select_value = value
              && not (List.mem_assoc "selected" resolved)
            then resolved @ [ ("selected", "") ]
            else resolved
          in
          Buffer.add_char b '<';
          Buffer.add_string b tag;
          List.iter
            (fun (name, v) ->
              Buffer.add_char b ' ';
              Buffer.add_string b name;
              Buffer.add_string b "=\"";
              Buffer.add_string b (escape ~quote:true v);
              Buffer.add_char b '"')
            resolved;
          Buffer.add_char b '>';
          after_text := false;
          if not (List.mem tag void_tags) then begin
            (match (tag, value) with
            | "textarea", Some v ->
                if String.length v > 0 && v.[0] = '\n' then
                  Buffer.add_char b '\n';
                Buffer.add_string b (escape ~quote:false v)
            | "select", _ ->
                let outer = !select_value in
                select_value := value;
                List.iter go children;
                select_value := outer
            | _ -> List.iter go children);
            Buffer.add_string b "</";
            Buffer.add_string b tag;
            Buffer.add_char b '>';
            after_text := false
          end
    in
    go root;
    Buffer.contents b

  let session ~streaming ~islands_only =
    { streaming; islands_only; islands = 0; asyncs = 0; awaits = 0; pending = []; preload = None;
      preloaded = []; depth = 0; queued = [] }

  let take_pending s =
    let p = List.rev s.pending in
    s.pending <- [];
    p

  let take_links s =
    let l = String.concat "" (List.rev s.queued) in
    s.queued <- [];
    l

  let rec print s build =
    let b = Buffer.create 256 in
    let after_text = ref false in
    let select_value = ref None in
    let hydrating () = (not s.islands_only) || s.depth > 0 in
    let marker m =
      if hydrating () then Buffer.add_string b m;
      after_text := false
    in
    let rec go = function
      | Text "" -> ()
      | Text t ->
          if !after_text && hydrating () then Buffer.add_string b "<!---->";
          Buffer.add_string b (escape ~quote:false t);
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
                let outer = s.depth in
                s.depth <- (if inside then max outer 1 else outer);
                match f () with
                | r ->
                    s.depth <- outer;
                    r
                | exception e ->
                    s.depth <- outer;
                    raise e
              in
              s.awaits <- s.awaits + 1;
              let id = "s" ^ string_of_int s.awaits in
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
              Buffer.add_string b ("<!--[" ^ id ^ "-->");
              after_text := false;
              go loading;
              Buffer.add_string b "<!--]-->";
              after_text := false
          | _ ->
              marker "<!--[-->";
              go (body ());
              marker "<!--]-->")
      | Template { node; _ } -> go node
      | Slot { content; _ } ->
          marker "<!--[$-->";
          Option.iter go content;
          marker "<!--]-->"
      | Island { name; props; render; loading } ->
          s.islands <- s.islands + 1;
          let id = "i" ^ string_of_int s.islands in
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
          | Some l when s.depth = 0 -> Buffer.add_string b l
          | Some l -> s.queued <- l :: s.queued
          | None -> ());
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
          s.depth <- s.depth + 1;
          (match go (render ()) with
          | () -> s.depth <- s.depth - 1
          | exception e ->
              s.depth <- s.depth - 1;
              raise e);
          Buffer.add_string b "</yuka-island>";
          Buffer.add_string b
            ("<script type=\"application/json\" data-yuka-props=\"" ^ id ^ "\">"
            ^ Json.to_string props ^ "</script>");
          if s.depth = 0 then begin
            List.iter (Buffer.add_string b) (List.rev s.queued);
            s.queued <- []
          end;
          after_text := false
      | Each { items; key = _; equal = _; render } ->
          marker "<!--[-->";
          List.iter
            (fun item ->
              marker "<!--[-->";
              go (render item);
              marker "<!--]-->")
            (items ());
          marker "<!--]-->"
      | Element { tag; attrs; children } ->
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
            if tag = "select" || tag = "textarea" then
              List.filter (fun (name, _) -> name <> "value") resolved
            else if
              tag = "option" && value <> None && !select_value = value
              && not (List.mem_assoc "selected" resolved)
            then resolved @ [ ("selected", "") ]
            else resolved
          in
          Buffer.add_char b '<';
          Buffer.add_string b tag;
          List.iter
            (fun (name, v) ->
              Buffer.add_char b ' ';
              Buffer.add_string b name;
              Buffer.add_string b "=\"";
              Buffer.add_string b (escape ~quote:true v);
              Buffer.add_char b '"')
            resolved;
          Buffer.add_char b '>';
          after_text := false;
          if not (List.mem tag void_tags) then begin
            (match (tag, value) with
            | "textarea", Some v ->
                if String.length v > 0 && v.[0] = '\n' then
                  Buffer.add_char b '\n';
                Buffer.add_string b (escape ~quote:false v)
            | "select", _ ->
                let outer = !select_value in
                select_value := value;
                List.iter go children;
                select_value := outer
            | _ -> List.iter go children);
            Buffer.add_string b "</";
            Buffer.add_string b tag;
            Buffer.add_char b '>';
            after_text := false
          end
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
        raise e);
    Buffer.contents b

  let render_html build = print (session ~streaming:false ~islands_only:false) build

  let to_html root = render_html (fun () -> root)
