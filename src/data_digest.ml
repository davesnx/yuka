let secret =
  lazy
    (match In_channel.with_open_bin "/dev/urandom" (fun channel -> really_input_string channel 16) with
    | bytes -> bytes
    | exception (Sys_error _ | End_of_file) ->
        let state = Random.State.make_self_init () in
        String.init 16 (fun _ -> Char.chr (Random.State.int state 256)))

let of_value data =
  match Marshal.to_string data [ Marshal.Closures ] with
  | bytes -> Some (Digest.to_hex (Digest.string (Lazy.force secret ^ bytes)))
  | exception (Failure _ | Invalid_argument _) -> None
