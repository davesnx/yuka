type element

external root : element = "documentElement" [@@mel.scope "document"]
external current : element Js.nullable = "fullscreenElement" [@@mel.scope "document"]
external request : element -> unit Js.Promise.t = "requestFullscreen" [@@mel.send]
external exit : unit -> unit Js.Promise.t = "exitFullscreen" [@@mel.scope "document"]

(* A browser can refuse: the promise is rejected, and the page stays as it is. *)
let toggle () =
  match if Js.Nullable.isNullable current then request root else exit () with
  | promise -> ignore (Js.Promise.catch (fun _ -> Js.Promise.resolve ()) promise)
  | exception _ -> ()
