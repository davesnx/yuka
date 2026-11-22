type page = { headers : (string * string) list; body : string }
type entry = { value : page; tags : string list; bytes : int; stamp : int }

type store = {
  table : (string, entry) Hashtbl.t;
  order : (string * int) Queue.t;
  mutable bytes : int;
  mutable stamp : int;
  mutable generation : int;
}

let s = { table = Hashtbl.create 64; order = Queue.create (); bytes = 0; stamp = 0; generation = 0 }

let generation () = s.generation

let remove key =
  match Hashtbl.find_opt s.table key with
  | Some e ->
      Hashtbl.remove s.table key;
      s.bytes <- s.bytes - e.bytes
  | None -> ()

let find key = Option.map (fun e -> e.value) (Hashtbl.find_opt s.table key)

let compact () =
  if Queue.length s.order > (2 * Hashtbl.length s.table) + 16 then begin
    let live = Queue.create () in
    Queue.iter
      (fun ((key, stamp) as item) ->
        match Hashtbl.find_opt s.table key with
        | Some e when e.stamp = stamp -> Queue.add item live
        | _ -> ())
      s.order;
    Queue.clear s.order;
    Queue.transfer live s.order
  end

let rec evict limit =
  if s.bytes > limit then
    match Queue.take_opt s.order with
    | None -> ()
    | Some (key, stamp) ->
        (match Hashtbl.find_opt s.table key with Some e when e.stamp = stamp -> remove key | _ -> ());
        evict limit

let add ~limit ~since key ~tags value =
  let bytes =
    String.length key + String.length value.body
    + List.fold_left (fun n (a, b) -> n + String.length a + String.length b) 0 value.headers
  in
  if since = s.generation && bytes <= limit then begin
    remove key;
    s.stamp <- s.stamp + 1;
    Hashtbl.replace s.table key { value; tags; bytes; stamp = s.stamp };
    s.bytes <- s.bytes + bytes;
    Queue.add (key, s.stamp) s.order;
    evict limit;
    compact ()
  end

let drop tags =
  match tags with
  | [] -> ()
  | _ ->
      s.generation <- s.generation + 1;
      let hit =
        Hashtbl.fold
          (fun key e acc -> if List.exists (fun t -> List.exists (String.equal t) tags) e.tags then key :: acc else acc)
          s.table []
      in
      List.iter remove hit;
      compact ()
