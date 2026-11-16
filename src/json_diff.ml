let max_edits = 256

let op name path rest : Json.t = `List (`String name :: `List (List.rev path) :: rest)

let distinct fields =
  let seen = Hashtbl.create 16 in
  List.for_all
    (fun (k, _) ->
      (not (Hashtbl.mem seen k))
      &&
      (Hashtbl.replace seen k ();
       true))
    fields

let matches (a : Json.t array) (b : Json.t array) =
  let n = Array.length a and m = Array.length b in
  let prefix = ref 0 in
  while !prefix < n && !prefix < m && a.(!prefix) = b.(!prefix) do
    incr prefix
  done;
  let suffix = ref 0 in
  while !suffix < n - !prefix && !suffix < m - !prefix && a.(n - 1 - !suffix) = b.(m - 1 - !suffix) do
    incr suffix
  done;
  let start = !prefix and n' = n - !prefix - !suffix and m' = m - !prefix - !suffix in
  let ha = Array.init n' (fun i -> Hashtbl.hash a.(start + i))
  and hb = Array.init m' (fun i -> Hashtbl.hash b.(start + i)) in
  let equal x y = ha.(x) = hb.(y) && a.(start + x) = b.(start + y) in
  let limit = min (n' + m') max_edits in
  let offset = limit + 1 in
  let v = Array.make ((2 * limit) + 3) 0 in
  let trace = ref [] in
  let rec step d =
    if d > limit then None
    else
      let rec diagonal k =
        if k > d then None
        else begin
          let x =
            if k = -d || (k <> d && v.(offset + k - 1) < v.(offset + k + 1)) then v.(offset + k + 1)
            else v.(offset + k - 1) + 1
          in
          let x = ref x in
          while !x < n' && !x - k < m' && equal !x (!x - k) do
            incr x
          done;
          v.(offset + k) <- !x;
          if !x >= n' && !x - k >= m' then Some d else diagonal (k + 2)
        end
      in
      let found = diagonal (-d) in
      trace := Array.sub v (offset - d) ((2 * d) + 1) :: !trace;
      match found with Some d -> Some d | None -> step (d + 1)
  in
  match step 0 with
  | None -> None
  | Some edits ->
      let pairs = ref [] in
      let x = ref n' and y = ref m' in
      let snake_to px py =
        while !x > px && !y > py do
          decr x;
          decr y;
          pairs := (start + !x, start + !y) :: !pairs
        done
      in
      let rec back d steps =
        match steps with
        | _ :: (previous :: _ as rest) when d > 0 ->
            let at k = previous.(k + d - 1) in
            let k = !x - !y in
            let k' = if k = -d || (k <> d && at (k - 1) < at (k + 1)) then k + 1 else k - 1 in
            let px = at k' in
            snake_to px (px - k');
            x := px;
            y := px - k';
            back (d - 1) rest
        | _ -> snake_to 0 0
      in
      back edits !trace;
      Some
        (List.init start (fun i -> (i, i))
        @ !pairs
        @ List.init !suffix (fun i -> (n - !suffix + i, m - !suffix + i)))

let rec diff_into emit path (a : Json.t) (b : Json.t) =
  if a = b then ()
  else
    match (a, b) with
    | `Assoc fa, `Assoc fb when distinct fa && distinct fb ->
        let in_b = Hashtbl.create 16 and in_a = Hashtbl.create 16 in
        List.iter (fun (k, v) -> Hashtbl.replace in_b k v) fb;
        List.iter (fun (k, v) -> Hashtbl.replace in_a k v) fa;
        let kept = List.filter (fun (k, _) -> Hashtbl.mem in_b k) fa in
        let added = List.filter (fun (k, _) -> not (Hashtbl.mem in_a k)) fb in
        if List.map fst (kept @ added) <> List.map fst fb then emit (op "r" path [ b ])
        else begin
          List.iter (fun (k, _) -> if not (Hashtbl.mem in_b k) then emit (op "x" (`String k :: path) [])) fa;
          List.iter (fun (k, v) -> diff_into emit (`String k :: path) v (Hashtbl.find in_b k)) kept;
          List.iter (fun (k, v) -> emit (op "a" (`String k :: path) [ v ])) added
        end
    | `List la, `List lb -> (
        let xa = Array.of_list la and xb = Array.of_list lb in
        match matches xa xb with
        | None -> emit (op "r" path [ b ])
        | Some pairs ->
            let hunks = ref [] in
            let rec gaps i j = function
              | (i', j') :: rest ->
                  if i' > i || j' > j then hunks := (i, i', j, j') :: !hunks;
                  gaps (i' + 1) (j' + 1) rest
              | [] -> if Array.length xa > i || Array.length xb > j then hunks := (i, Array.length xa, j, Array.length xb) :: !hunks
            in
            gaps 0 0 pairs;
            List.iter
              (fun (i1, i2, j1, j2) ->
                let common = min (i2 - i1) (j2 - j1) in
                for i = i2 - 1 downto i1 + common do
                  emit (op "x" (`Int i :: path) [])
                done;
                for t = common to j2 - j1 - 1 do
                  emit (op "a" (`Int (i1 + t) :: path) [ xb.(j1 + t) ])
                done;
                for t = 0 to common - 1 do
                  diff_into emit (`Int (i1 + t) :: path) xa.(i1 + t) xb.(j1 + t)
                done)
              !hunks)
    | _ -> emit (op "r" path [ b ])

let diff a b =
  let ops = ref [] in
  diff_into (fun o -> ops := o :: !ops) [] a b;
  List.rev !ops
