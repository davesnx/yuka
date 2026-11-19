open Demo_shared.Model

let placeholder () =
  Block_stubs.component ~markup:"<span></span>" ~walk:[||] ~targets:[||] ~kinds:[||] (fun _ _ -> [||])

let avatar_props ~(user : User.t option) () = (user, ())
let avatar : (User.t option * unit) Block.component = placeholder ()
let status_icon_props ~(status : Issue.status) () = (status, ())
let status_icon : (Issue.status * unit) Block.component = placeholder ()
let priority_icon_props ~(priority : Issue.priority) () = (priority, ())
let priority_icon : (Issue.priority * unit) Block.component = placeholder ()
let labels_props ~(labels : string list) () = (labels, ())
let labels : (string list * unit) Block.component = placeholder ()
