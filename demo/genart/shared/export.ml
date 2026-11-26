(* Saves the drawing as a PNG. The shared library also builds for native code, so the
   canvas code is in client/main.ml, which sets this. The argument is the file name. *)
let png : (string -> unit) ref = ref (fun _ -> ())
