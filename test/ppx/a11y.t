  $ cat > yuka.ml <<'X'
  > let runtime_template _ ~html:_ ~walk:_ ~kids:_ ~attrs:_ ~values:_ ~clones:_ = ()
  > let runtime_instance _ _ = ()
  > let runtime_attribute _ = ()
  > let runtime_child _ = ()
  > let runtime_hole _ = ()
  > let runtime_attribute_option _ = ()
  > let runtime_attr _ _ = ()
  > let element _ _ _ = ()
  > let text _ = ()
  > let on _ _ = ()
  > X
  $ ocamlfind ocamlc -c yuka.ml
  $ run() { mlx-pp $1.mlx > $1.ml && ocamlfind ocamlc -c -color never -error-style short -ppx "./pp.exe --as-ppx" $1.ml; }

An img with no alt:

  $ cat > img.mlx <<'X'
  > let bad = <img src="a.png" />
  > let empty = <img src="a.png" alt="" />
  > let optional alt = <img src="a.png" ?alt />
  > X
  $ run img
  File "img.mlx", line 1, characters 10-29:
  Warning 22 [preprocessor]: [yuka] <img> has no alt. Add alt="..." that tells what the image shows, or alt="" when the image is decoration.

A click handler on an element that is not interactive:

  $ cat > click.mlx <<'X'
  > let f _ = ()
  > let bad = <div on_click=f>"x"</div>
  > let role_only = <span on_click=f role=`button>"x"</span>
  > let button = <button on_click=f>"x"</button>
  > let link = <a href="/x" on_click=f>"x"</a>
  > let reachable = <div on_click=f role=`button tabindex=0>"x"</div>
  > let hidden = <div aria_hidden=true on_click=f />
  > let bar = <svg><g on_click=f><rect /></g></svg>
  > X
  $ run click
  File "click.mlx", line 2, characters 10-35:
  Warning 22 [preprocessor]: [yuka] <div> has on_click but a keyboard cannot use it. Use <button>, or add role and tabindex.
  
  File "click.mlx", line 3, characters 16-56:
  Warning 22 [preprocessor]: [yuka] <span> has on_click but a keyboard cannot use it. Use <button>, or add role and tabindex.

A label with no control:

  $ cat > label.mlx <<'X'
  > module Field = struct let make ~children () = children end
  > let bad = <label>"Name"</label>
  > let for_ = <label for_="name">"Name"</label>
  > let wrapped = <label>"Name" <span><input /></span></label>
  > let component = <label>"Name" <Field>"x"</Field></label>
  > let hole b = <label>"Name" (if b then <select /> else <textarea />)</label>
  > X
  $ run label
  File "label.mlx", line 2, characters 10-31:
  Warning 22 [preprocessor]: [yuka] <label> has no control. Add for_="id", or put the control in the label.

Each warning points at its own element, also in a nested element and in a hole:

  $ cat > nested.mlx <<'X'
  > let page b =
  >   <main>
  >     <img src="a.png" />
  >     (if b then <div on_click=(fun _ -> ())>"x"</div> else <label>"y"</label>)
  >   </main>
  > X
  $ run nested
  File "nested.mlx", line 3, characters 4-23:
  Warning 22 [preprocessor]: [yuka] <img> has no alt. Add alt="..." that tells what the image shows, or alt="" when the image is decoration.
  
  File "nested.mlx", line 4, characters 15-52:
  Warning 22 [preprocessor]: [yuka] <div> has on_click but a keyboard cannot use it. Use <button>, or add role and tabindex.
  
  File "nested.mlx", line 4, characters 58-76:
  Warning 22 [preprocessor]: [yuka] <label> has no control. Add for_="id", or put the control in the label.

A file can turn the warnings off:

  $ cat > off.mlx <<'X2'
  > [@@@warning "-22"]
  > let bad = <img src="a.png" />
  > X2
  $ run off
