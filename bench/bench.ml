open Yuka

external now : unit -> float = "now" [@@mel.scope "performance"]
external log : string -> unit = "log" [@@mel.scope "console"]

let make_container : unit -> Yuka_client.Dom.element =
  [%mel.raw
    "function () { const c = document.createElement('div'); document.body.appendChild(c); return c }"]

let remove_container : Yuka_client.Dom.element -> unit =
  [%mel.raw "function (c) { c.remove() }"]

let row ~wrap i =
  let selected = State.make false in
  let title = State.make ("Issue " ^ string_of_int i) in
  let tree =
    lower "li"
      [
        attr "class" "row";
        hole_attr "data-selected" (fun () ->
            if State.get selected then Some "1" else None);
        on "click" (fun _ -> State.set selected true);
      ]
      [
        lower "span" [ attr "class" "status" ] [ text "o" ];
        lower "span" [ attr "class" "prio" ] [ text "!" ];
        lower "a" [ attr "href" "#" ] [ hole (fun () -> text (State.get title)) ];
        lower "span" [ attr "class" "id" ]
          [ hole (fun () -> text ("YU-" ^ string_of_int i)) ];
        lower "time" [] [ text "2d" ];
      ]
  in
  if wrap then template "bench-row" tree else tree

let static_row ~wrap i =
  let tree =
    lower "li" [ attr "class" "row" ]
      [
        lower "span" [ attr "class" "status" ] [ text "o" ];
        lower "span" [ attr "class" "prio" ] [ text "!" ];
        lower "a" [ attr "href" "#" ] [ text "title" ];
        lower "span" [ attr "class" "id" ] [ text "YU-1" ];
        lower "time" [] [ text "2d" ];
      ]
  in
  ignore i;
  if wrap then template "bench-static" tree else tree

let once ?(static = false) wrap rows =
  let row = if static then static_row else row in
  let c = make_container () in
  let t0 = now () in
  let dispose =
    Yuka_client.render c (fun () ->
        lower "ul" []
          [
            each ~key:string_of_int
              (fun () -> List.init rows Fun.id)
              (fun i -> row ~wrap i);
          ])
  in
  let t1 = now () in
  dispose ();
  remove_container c;
  t1 -. t0

let best ?static wrap rows =
  for _ = 1 to 3 do
    ignore (once ?static wrap rows)
  done;
  let b = ref infinity in
  for _ = 1 to 10 do
    b := min !b (once ?static wrap rows)
  done;
  !b

let () =
  List.iter
    (fun rows ->
      let plain = best false rows in
      let templ = best true rows in
      let plain2 = best false rows in
      let templ2 = best true rows in
      let sp = best ~static:true false rows in
      let st = best ~static:true true rows in
      log (Printf.sprintf "STATIC rows=%d plain=%.1f template=%.1f" rows sp st);
      log
        (Printf.sprintf "RESULT rows=%d plain=%.1f template=%.1f plain2=%.1f template2=%.1f"
           rows plain templ plain2 templ2))
    [ 1000; 5000 ];
  log "DONE"
