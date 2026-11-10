import { createServer } from "node:http";
import { parseArgs } from "node:util";

const statuses = ["Backlog", "Todo", "In progress", "Done", "Canceled"];
const priorities = ["No priority", "Urgent", "High", "Medium", "Low"];
const users = ["Maya Chen", "Dev Patel", "Sofia Rossi", "Tomas Novak"];

const issue = (i) => ({
  id: `YUK-${i}`,
  title: `Issue ${i}: fix "quotes" & <tags> in the list`,
  status: statuses[i % 5],
  priority: priorities[i % 5],
  assignee: i % 3 === 0 ? null : users[i % 4],
  labels: [[], ["bug"], ["bug", "server"]][i % 3],
});

export const slug = (s) => s.toLowerCase().replaceAll(" ", "-");

export function serve(render) {
  const { values } = parseArgs({ options: { port: { type: "string", default: "8200" }, rows: { type: "string", default: "100" } } });
  const issues = Array.from({ length: Number(values.rows) }, (_, i) => issue(i + 1));
  createServer((req, res) => {
    if (req.url !== "/") {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(render(issues));
  }).listen(Number(values.port), "127.0.0.1");
}
