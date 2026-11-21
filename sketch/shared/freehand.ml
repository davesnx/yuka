type point = { x : float; y : float; pressure : float }

type options = {
  size : float;
  thinning : float;
  smoothing : float;
  streamline : float;
  simulate : bool;
  taper_start : float;
  taper_end : float;
}

let options ~size ~simulate ~complete =
  {
    size;
    thinning = (if simulate then 0.45 else 0.6);
    smoothing = 0.5;
    streamline = 0.45;
    simulate;
    taper_start = size *. 3.5;
    taper_end = (if complete then size *. 3.5 else 0.);
  }

type stroke_point = { p : Vec.t; pressure : float; vector : Vec.t; speed : float; running : float }

let fixed_pi = Float.pi +. 0.0001
let rate_of_pressure_change = 0.275
let ease_out_sine t = Float.sin (t *. Float.pi /. 2.)

let vec (p : point) = Vec.make p.x p.y

let stroke_points opts (input : point array) =
  let input =
    match Array.length input with
    | 1 -> [| input.(0); { (input.(0)) with x = input.(0).x +. 1.; y = input.(0).y +. 1. } |]
    | 2 ->
        let a = input.(0) and b = input.(1) in
        Array.init 5 (fun i ->
            let t = float_of_int i /. 4. in
            {
              x = a.x +. ((b.x -. a.x) *. t);
              y = a.y +. ((b.y -. a.y) *. t);
              pressure = a.pressure +. ((b.pressure -. a.pressure) *. t);
            })
    | _ -> input
  in
  let n = Array.length input in
  let t = 0.15 +. ((1. -. opts.streamline) *. 0.85) in
  let first = { p = vec input.(0); pressure = input.(0).pressure; vector = Vec.make 1. 1.; speed = 0.; running = 0. } in
  let out = ref [ first ] in
  let prev = ref first in
  let running = ref 0. in
  let reached = ref false in
  let travel = ref 0. in
  let push point ~pressure ~speed =
    running := !running +. Vec.dist point !prev.p;
    let next = { p = point; pressure; vector = Vec.normalize (Vec.sub !prev.p point); speed; running = !running } in
    out := next :: !out;
    prev := next
  in
  for i = 1 to n - 1 do
    let raw = vec input.(i) in
    travel := !travel +. Vec.dist raw (vec input.(i - 1));
    if i = n - 1 then begin
      if not (Vec.equal raw !prev.p) then push raw ~pressure:input.(i).pressure ~speed:!travel
    end
    else
      let point = Vec.lerp !prev.p raw t in
      if not (Vec.equal point !prev.p) then begin
        let ahead = !running +. Vec.dist point !prev.p in
        if !reached || ahead >= opts.size *. 0.25 then begin
          reached := true;
          push point ~pressure:input.(i).pressure ~speed:!travel;
          travel := 0.
        end
      end
  done;
  let step = opts.size *. 0.5 in
  let dense =
    List.fold_left
      (fun acc (b : stroke_point) ->
        match acc with
        | [] -> [ b ]
        | (a : stroke_point) :: _ ->
            let d = b.running -. a.running in
            let m = Float.to_int (d /. step) in
            let between =
              List.init m (fun k ->
                  let f = float_of_int (k + 1) /. float_of_int (m + 1) in
                  { b with p = Vec.lerp a.p b.p f; running = a.running +. (d *. f) })
            in
            (b :: List.rev between) @ acc)
      [] (List.rev !out)
  in
  let points = Array.of_list (List.rev dense) in
  if Array.length points > 1 then points.(0) <- { (points.(0)) with vector = points.(1).vector }
  else points.(0) <- { (points.(0)) with vector = Vec.zero };
  points

let radius_of opts pressure = opts.size *. (0.5 -. (opts.thinning *. (0.5 -. pressure)))

let simulated opts ~previous ~speed =
  let sp = Float.min 1. (speed /. opts.size) in
  let rp = Float.min 1. (1. -. sp) in
  Float.min 1. (previous +. ((rp -. previous) *. (sp *. rate_of_pressure_change)))

let dot center radius =
  Array.init 16 (fun i ->
      let a = Float.pi *. 2. *. float_of_int i /. 16. in
      Vec.make (center.Vec.x +. (radius *. Float.cos a)) (center.y +. (radius *. Float.sin a)))

let outline opts input =
  if Array.length input = 0 || opts.size <= 0. then [||]
  else
    let points = stroke_points opts input in
    let n = Array.length points in
    let total = points.(n - 1).running in
    let reach = Float.min (opts.size *. 2.) (total /. 2.) in
    let rec first_beyond i = if i >= n - 1 || points.(i).running >= reach then i else first_beyond (i + 1) in
    let rec last_before i = if i <= 0 || total -. points.(i).running >= reach then i else last_before (i - 1) in
    let j = first_beyond 0 and k = last_before (n - 1) in
    let head = Vec.normalize (Vec.sub points.(0).p points.(j).p) in
    let tail = Vec.normalize (Vec.sub points.(k).p points.(n - 1).p) in
    let onto (origin : Vec.t) (u : Vec.t) (p : Vec.t) = Vec.add origin (Vec.scale u (Vec.dot (Vec.sub p origin) u)) in
    let start = points.(0).p and finish = points.(n - 1).p in
    for i = 0 to n - 1 do
      if i <= j && j > 0 then points.(i) <- { (points.(i)) with p = onto start head points.(i).p; vector = head }
      else if i > k && k < n - 1 then points.(i) <- { (points.(i)) with p = onto finish tail points.(i).p; vector = tail }
    done;
    let grown = Num.clamp ~lo:0. ~hi:1. ((total -. (opts.size *. 2.)) /. (opts.size *. 4.)) in
    let taper limit = grown *. Float.min limit (total *. 0.3) in
    let opts = { opts with taper_start = taper opts.taper_start; taper_end = taper opts.taper_end } in
    let start_pressure =
      let acc = ref points.(0).pressure in
      for i = 0 to min 9 (n - 1) do
        let p = points.(i) in
        let pressure = if opts.simulate then simulated opts ~previous:!acc ~speed:p.speed else p.pressure in
        acc := (!acc +. pressure) /. 2.
      done;
      !acc
    in
    if n = 1 || total < opts.size /. 4. then dot points.(0).p (Float.max 0.5 (radius_of opts start_pressure))
    else begin
      let left = ref [] and right = ref [] in
      let prev_pressure = ref start_pressure in
      let radius = ref (radius_of opts points.(n - 1).pressure) in
      let prev_vector = ref points.(0).vector in
      let pl = ref points.(0).p and pr = ref points.(0).p in
      let prev_sharp = ref false in
      let min_distance = (opts.size *. opts.smoothing) ** 2. in
      for i = 0 to n - 1 do
        let { p = point; pressure; vector; speed; running } = points.(i) in
        if not (i < n - 1 && total -. running < 0.5) then begin
          let pressure =
            if opts.simulate then simulated opts ~previous:!prev_pressure ~speed else pressure
          in
          let r = radius_of opts pressure in
          let ts = if running < opts.taper_start then ease_out_sine (running /. opts.taper_start) else 1. in
          let te =
            if total -. running < opts.taper_end then ease_out_sine ((total -. running) /. opts.taper_end) else 1.
          in
          radius := Float.max 0.01 (r *. Float.min ts te);
          let next_vector = if i < n - 1 then points.(i + 1).vector else vector in
          let next_dpr = if i < n - 1 then Vec.dot vector next_vector else 1. in
          let prev_dpr = Vec.dot vector !prev_vector in
          let sharp = prev_dpr < 0. && not !prev_sharp in
          let next_sharp = next_dpr < 0. in
          if sharp || next_sharp then begin
            let offset = Vec.scale (Vec.perp !prev_vector) !radius in
            for step = 0 to 13 do
              let t = float_of_int step /. 13. in
              let tl = Vec.rotate_about ~center:point (Vec.sub point offset) (fixed_pi *. t) in
              let tr = Vec.rotate_about ~center:point (Vec.add point offset) (-.fixed_pi *. t) in
              left := tl :: !left;
              right := tr :: !right;
              pl := tl;
              pr := tr
            done;
            if next_sharp then prev_sharp := true
          end
          else begin
            prev_sharp := false;
            if i = n - 1 then begin
              let offset = Vec.scale (Vec.perp vector) !radius in
              left := Vec.sub point offset :: !left;
              right := Vec.add point offset :: !right
            end
            else begin
              let offset = Vec.scale (Vec.perp (Vec.lerp next_vector vector next_dpr)) !radius in
              let tapering = ts < 1. || te < 1. in
              let tl = Vec.sub point offset in
              if i <= 1 || tapering || Vec.dist2 !pl tl > min_distance then begin
                left := tl :: !left;
                pl := tl
              end;
              let tr = Vec.add point offset in
              if i <= 1 || tapering || Vec.dist2 !pr tr > min_distance then begin
                right := tr :: !right;
                pr := tr
              end;
              prev_pressure := pressure;
              prev_vector := vector
            end
          end
        end
      done;
      let first = points.(0).p and last = points.(n - 1).p in
      let right_list = List.rev !right in
      let start_cap =
        if opts.taper_start > 0. then []
        else
          match right_list with
          | [] -> []
          | r0 :: _ ->
              List.init 13 (fun k -> Vec.rotate_about ~center:first r0 (fixed_pi *. float_of_int (k + 1) /. 13.))
      in
      let end_cap =
        if opts.taper_end > 0. then [ last ]
        else
          let direction = Vec.perp (Vec.neg points.(n - 1).vector) in
          let start = Vec.add last (Vec.scale direction !radius) in
          List.init 28 (fun k -> Vec.rotate_about ~center:last start (fixed_pi *. 3. *. float_of_int (k + 1) /. 29.))
      in
      Array.of_list (List.rev_append !left (end_cap @ !right @ start_cap))
    end

let path_of_outline points =
  let n = Array.length points in
  if n < 4 then ""
  else
    let b = Buffer.create (n * 14) in
    let num v = Buffer.add_string b (Num.to_string v) in
    let pair (p : Vec.t) =
      num p.x;
      Buffer.add_char b ',';
      num p.y
    in
    Buffer.add_char b 'M';
    pair (Vec.mid points.(n - 1) points.(0));
    Buffer.add_string b "Q";
    pair points.(0);
    Buffer.add_char b ' ';
    pair (Vec.mid points.(0) points.(1));
    Buffer.add_string b "T";
    for i = 1 to n - 1 do
      if i > 1 then Buffer.add_char b ' ';
      pair (Vec.mid points.(i) points.((i + 1) mod n))
    done;
    Buffer.add_char b 'Z';
    Buffer.contents b

let path opts input = path_of_outline (outline opts input)
