let cleanup_table : (unit -> unit) Host.table option ref = ref None

let cleanups () =
  match !cleanup_table with
  | Some t -> t
  | None ->
      let t = Host.table () in
      cleanup_table := Some t;
      t

let set_cleanup id f = Host.table_set (cleanups ()) (string_of_int id) f
let drop_cleanup id = Host.table_delete (cleanups ()) (string_of_int id)

let next_cleanup = ref 0

let register cleanup =
  incr next_cleanup;
  set_cleanup !next_cleanup cleanup;
  !next_cleanup

let field name fields =
  List.find_map (fun (k, v) -> if String.equal k name then Some v else None) fields

let has_value value id = match value with Some v -> String.equal v id | None -> false

let async_value id =
  let result, resolve, fail = Async.make () in
  let find () =
    let found =
      List.find_opt
        (fun s -> has_value (Host.get_attribute s "data-yuka-async") id)
        (Array.to_list
           (Host.query_all (Host.document ()) "script[data-yuka-async]"))
    in
    match found with
    | None -> false
    | Some script when Host.text_content script = "" -> false
    | Some script when
        Host.ready_state () = "loading"
        && Result.is_error (Json.of_string (Host.text_content script)) ->
        false
    | Some script ->
        (match Json.of_string (Host.text_content script) with
        | Ok (`Assoc fields) -> (
            match (field "ok" fields, field "error" fields) with
            | Some value, _ -> resolve value
            | None, Some (`String message) -> fail message
            | None, _ -> fail ("async value " ^ id ^ ": unexpected shape"))
        | Ok _ -> fail ("async value " ^ id ^ ": unexpected shape")
        | Error message -> fail ("async value " ^ id ^ ": bad JSON: " ^ message));
        true
  in
  if not (find ()) then begin
    let cleanup_id = register ignore in
    let touches nodes =
      Array.exists
        (fun n ->
          let own = if Host.local_name n = "script" then [| n |] else [||] in
          Array.exists
            (fun s -> has_value (Host.get_attribute s "data-yuka-async") id)
            (Array.append own (Host.query_all n "script[data-yuka-async]")))
        nodes
    in
    let disconnect =
      Host.watch_added (fun nodes ->
          touches nodes
          && find ()
          && (drop_cleanup cleanup_id;
              true))
    in
    set_cleanup cleanup_id disconnect
  end;
  result

let async_hook : (string -> Json.t Async.t) ref =
  ref (fun id -> failwith ("Yuka: no reader for async value " ^ id ^ ": Codec.async did not call Async_reader.use_async"))

let use_async () = async_hook := async_value
