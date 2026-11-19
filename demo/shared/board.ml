include Board_types

let%action move =
  Yuka.Action.mutation ~input:move_codec ~output:codec (fun _ { workspace; id; x; y } ->
      Store.write workspace
        (fun () ->
          if not (Store.on_board workspace id) then Error ("No item " ^ id)
          else if not (inside ~x ~y) then Error "The position is outside the board"
          else Ok (Store.move_item workspace ~id ~x ~y))
        (fun () -> Store.publish_board workspace))

let%action add_note =
  Yuka.Action.mutation ~input:note_codec ~output:codec (fun _ { workspace; text } ->
      let text = String.trim text in
      if text = "" then Yuka.Server.Action.reject "Note is empty"
      else if not (String.is_valid_utf_8 text) then Yuka.Server.Action.reject "Note is not valid UTF-8 text"
      else if String.fold_left (fun count char -> if Char.code char land 0xC0 = 0x80 then count else count + 1) 0 text > note_length then
        Yuka.Server.Action.reject (Printf.sprintf "Note is too long (at most %d characters)" note_length)
      else
        Store.write workspace
          (fun () ->
            if Store.note_total workspace >= note_limit then
              Error (Printf.sprintf "The board has %d notes, the most it can have" note_limit)
            else Ok (Store.add_note workspace ~text))
          (fun () -> Store.publish_board workspace))

let%action remove_note =
  Yuka.Action.mutation ~input:remove_codec ~output:codec (fun _ { workspace; note_id } ->
      Store.write workspace
        (fun () -> if Store.remove_note workspace ~id:note_id then Ok () else Error ("No note " ^ note_id))
        (fun () -> Store.publish_board workspace))

let%action shuffle =
  Yuka.Action.mutation ~input:Model.Workspace.codec ~output:codec (fun _ workspace ->
      Store.write workspace (fun () -> Ok (Store.shuffle workspace)) (fun () -> Store.publish_board workspace))
