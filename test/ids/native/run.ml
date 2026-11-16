let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    Printf.printf "FAIL %s\n  expected: %s\n  got:      %s\n" name expected got
  end

let read file = In_channel.with_open_bin file In_channel.input_all

let values html before =
  let n = String.length before in
  let rec go i acc =
    match String.index_from_opt html i before.[0] with
    | None -> List.rev acc
    | Some j when j + n <= String.length html && String.sub html j n = before ->
        let stop = String.index_from html (j + n) '"' in
        go stop (String.sub html (j + n) (stop - j - n) :: acc)
    | Some j -> go (j + 1) acc
  in
  go 0 []

let island prefix id = List.map (fun n -> prefix ^ id ^ "-" ^ n) [ "1"; "2"; "3-1"; "3-2"; "4"; "5"; "6"; "7" ]

let ids file expected =
  let html = read file in
  let inputs = values html "<input id=\"" in
  check (file ^ ": input ids") (String.concat " " expected) (String.concat " " inputs);
  check (file ^ ": labels") (String.concat " " inputs) (String.concat " " (values html "<label for=\""))

let () =
  ids "filled.html" (("p-1" :: island "" "i1") @ [ "i2-1"; "p-2"; "i2-2" ] @ island "" "i3");
  ids "shell.html"
    ([ "p-1"; "i1-1"; "i1-2"; "i1-3-1"; "i1-4"; "i1-5"; "i1-6"; "i1-7"; "i2-1"; "p-2"; "i2-2" ]
    @ [ "i3-1"; "i3-2"; "i3-3-1"; "i3-4"; "i3-5"; "i3-6"; "i3-7" ]);
  ids "answer.html" ("L1/x-p-1" :: island "L1/x-" "i1");
  if !failures > 0 then exit 1
