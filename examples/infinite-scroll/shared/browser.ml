(* What the islands need from the browser and Yuka does not give. The client entry
   (client/main.ml) sets it; on the server it keeps this default and is never called. *)

(* Calls the function once, when the element with this id comes into view; gives the
   function that stops watching. *)
let on_visible : (string -> (unit -> unit) -> unit -> unit) ref = ref (fun _ _ () -> ())
