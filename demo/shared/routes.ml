let index () = Yuka.Router.root
let my () = Yuka.Router.s "my"
let issue () = Yuka.Router.(s "issue" / string)
let index_url = Yuka.Router.href (index ())
let my_url = Yuka.Router.href (my ())
let issue_url id = Yuka.Router.href (issue ()) id
