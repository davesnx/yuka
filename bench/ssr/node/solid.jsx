import { For } from "solid-js";
import { renderToString } from "solid-js/web";
import { serve, slug } from "../../data.js";

const Row = (props) => (
  <li class="issue">
    <a class="row" href={`/issue/${props.issue.id}`}>
      <span class="id">{props.issue.id}</span>
      <span class="title">{props.issue.title}</span>
      <span class={`status status-${slug(props.issue.status)}`}>{props.issue.status}</span>
      <span class="priority">{props.issue.priority}</span>
      <span class="assignee">{props.issue.assignee ?? "Unassigned"}</span>
      <span class="labels">
        <For each={props.issue.labels}>{(l) => <span class="label">{l}</span>}</For>
      </span>
    </a>
  </li>
);

const Page = (props) => (
  <html>
    <head>
      <meta charset="utf-8" />
      <title>Issues</title>
      <link rel="stylesheet" href="/static/style.css" />
    </head>
    <body>
      <main>
        <h1>All issues</h1>
        <ul class="issues">
          <For each={props.issues}>{(i) => <Row issue={i} />}</For>
        </ul>
      </main>
    </body>
  </html>
);

serve((issues) => "<!DOCTYPE html>" + renderToString(() => <Page issues={issues} />));
