open Types

  type 'a t = { encode : 'a -> Json.t; decode : Json.t -> ('a, string) result }

  let mismatch what (j : Json.t) =
    let s = Json.to_string j in
    let s = if String.length s > 40 then String.sub s 0 40 ^ "..." else s in
    Error ("expected " ^ what ^ ", got " ^ s)

  let int =
    { encode = (fun i -> `Int i);
      decode = (function `Int i -> Ok i | j -> mismatch "int" j) }

  let float =
    { encode = (fun f -> `Float f);
      decode =
        (function
        | `Float f -> Ok f
        | `Int i -> Ok (float_of_int i)
        | j -> mismatch "float" j) }

  let string =
    { encode = (fun s -> `String s);
      decode = (function `String s -> Ok s | j -> mismatch "string" j) }

  let bool =
    { encode = (fun b -> `Bool b);
      decode = (function `Bool b -> Ok b | j -> mismatch "bool" j) }

  let unit =
    { encode = (fun () -> `Null);
      decode = (function `Null -> Ok () | j -> mismatch "null" j) }

  let list c =
    { encode = (fun l -> `List (List.map c.encode l));
      decode =
        (function
        | `List l ->
            let rec go acc = function
              | [] -> Ok (List.rev acc)
              | x :: rest -> (
                  match c.decode x with
                  | Ok v -> go (v :: acc) rest
                  | Error _ as e -> e)
            in
            go [] l
        | j -> mismatch "list" j) }

  let array c =
    let l = list c in
    { encode = (fun a -> l.encode (Array.to_list a));
      decode = (fun j -> Result.map Array.of_list (l.decode j)) }

  let option c =
    { encode = (function None -> `Null | Some v -> c.encode v);
      decode =
        (function `Null -> Ok None | j -> Result.map Option.some (c.decode j)) }

  let result a e =
    {
      encode =
        (function
        | Ok v -> `Assoc [ ("ok", a.encode v) ]
        | Error v -> `Assoc [ ("error", e.encode v) ]);
      decode =
        (function
        | `Assoc [ ("ok", j) ] -> Result.map (fun v -> Ok v) (a.decode j)
        | `Assoc [ ("error", j) ] -> Result.map (fun v -> Error v) (e.decode j)
        | j -> mismatch "result" j);
    }

  let encode c v = c.encode v
  let decode c j = c.decode j

let async c : 'a Async.t t =
  {
    encode =
      (fun a ->
        let j = Async.map c.encode a in
        let id, streaming =
          match !current_session with
          | Some s ->
              s.asyncs <- s.asyncs + 1;
              (s.id_prefix ^ "a" ^ string_of_int s.asyncs, s.streaming)
          | None -> ("a0", false)
        in
        let assoc extra : Json.t = `Assoc (("$async", `String id) :: extra) in
        match Async.status j with
        | Async.Done v -> assoc [ ("ok", v) ]
        | Async.Failed m -> assoc [ ("error", `String (async_error id m)) ]
        | Async.Pending -> (
            match !current_session with
            | Some s when streaming ->
                s.pending <- Pending_async { id; async = j } :: s.pending;
                assoc []
            | _ -> assoc [ ("error", `String "pending at render") ]));
    decode =
      (function
      | `Assoc (("$async", `String id) :: rest) -> (
          let of_json j =
            match c.decode j with
            | Ok v -> Async.return v
            | Error m -> Async.failed m
          in
          match rest with
          | [ ("ok", j) ] -> Ok (of_json j)
          | [ ("error", `String m) ] -> Ok (Async.failed m)
          | [] -> Ok (Async.bind (!async_source id) of_json)
          | _ -> Error "bad async reference")
      | j -> mismatch "async reference" j);
  }

let slot : slot t =
  {
    encode = (fun _ -> `Null);
    decode = (fun _ -> Ok { content = None; dom = ref [] });
  }
