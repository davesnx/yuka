import { createElement as h } from "react";
import { renderToString } from "react-dom/server";
import { serve, slug } from "./data.js";

const Row = ({ issue: i }) =>
  h(
    "li",
    { className: "issue" },
    h(
      "a",
      { className: "row", href: `/issue/${i.id}` },
      h("span", { className: "id" }, i.id),
      h("span", { className: "title" }, i.title),
      h("span", { className: `status status-${slug(i.status)}` }, i.status),
      h("span", { className: "priority" }, i.priority),
      h("span", { className: "assignee" }, i.assignee ?? "Unassigned"),
      h("span", { className: "labels" }, i.labels.map((l) => h("span", { className: "label", key: l }, l))),
    ),
  );

const Page = ({ issues }) =>
  h(
    "html",
    null,
    h("head", null, h("meta", { charSet: "utf-8" }), h("title", null, "Issues"), h("link", { rel: "stylesheet", href: "/static/style.css" })),
    h("body", null, h("main", null, h("h1", null, "All issues"), h("ul", { className: "issues" }, issues.map((i) => h(Row, { issue: i, key: i.id }))))),
  );

serve((issues) => "<!DOCTYPE html>" + renderToString(h(Page, { issues })));
