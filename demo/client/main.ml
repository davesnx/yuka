open Demo_shared

let () =
  Yuka.Router.start
    ~lazy_entries:
      [
        [%yuka.lazy Demo_shared.Issue_props "../shared/issue_props.js"];
        [%yuka.lazy Demo_shared.Related "../shared/related.js"];
        [%yuka.lazy Demo_shared.Comments "../shared/comments.js"];
      ]
    [ Issue_list.register; Counter.register; New_issue.register ]
