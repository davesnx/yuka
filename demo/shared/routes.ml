let index () = Yuka_router.root
let my () = Yuka_router.s "my"
let issue () = Yuka_router.(s "issue" / string)
let index_url = Yuka_router.href (index ())
let my_url = Yuka_router.href (my ())
let issue_url id = Yuka_router.href (issue ()) id
