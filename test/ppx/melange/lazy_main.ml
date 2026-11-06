let entry = [%yuka.lazy Demo_shared.Issue_props "../shared/issue_props.js"]
let () = Yuka_client.start ~lazy_entries:[ entry ] []
