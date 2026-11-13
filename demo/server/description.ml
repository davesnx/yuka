let yuk_1 =
  {|A hole inside an `each` item loses its marker when the item is empty. Reproduce with a filter that matches nothing, then clear it.

## Steps

1. Open the issue list.
2. Type `zzz` in the filter: no row matches.
3. Clear the filter.

The rows come back, but the **first hole** of each row no longer updates.

## Cause

The printer writes the closing marker only when the item has children:

```ocaml
let print_hole buffer ~children =
  Buffer.add_string buffer "<!--[-->";
  List.iter (print buffer) children;
  if children <> [] then Buffer.add_string buffer "<!--]-->"
```

> The client looks for the closing marker to know where the hole ends. With no marker it takes the next sibling.

See the [hydration notes](https://github.com/davesnx/yuka/blob/main/docs/islands.md) for the marker format.|}

let yuk_2 =
  {|Send the shell first and the comments later in the same response, with out of order placement.

| Part | Sent | Placed by |
| --- | --- | --- |
| Shell | first chunk | the HTML parser |
| Comments | when the query ends | `__yukaFill` |
| Related issues | last | `__yukaFill` |

The fill script moves each part into its slot:

```javascript
function fill(id) {
  const template = document.getElementById(`yuka-fill-${id}`);
  const slot = document.querySelector(`[data-yuka-slot="${id}"]`);
  slot.replaceWith(template.content);
}
```|}

let yuk_5 =
  {|The client reads the JSON script of each island and decodes the props with the codec.

The server prints the props next to the island:

```json
{
  "issue_id": "YUK-5",
  "me": { "id": "maya", "name": "Maya Chen" },
  "comments": []
}
```

The client decodes them with the codec of the props:

```ocaml
type props = { issue_id : string; me : User.t }

let decode json =
  match Yuka.Codec.decode props_codec json with
  | Ok props -> render props
  | Error message -> Console.error message
```

- [x] Records and variants
- [x] Lists and options
- [ ] Recursive types|}

let yuk_10 =
  {|POST the new status and answer with the updated issue.

```shell
curl -X POST http://localhost:8080/_yuka/action/update_issue \
  -H 'Content-Type: application/json' \
  -d '{"id":"YUK-4","status":"Done"}'
```

The answer is the issue as JSON. A missing issue answers `422` with the message *No issue YUK-4*.|}

let yuk_12 =
  {|Raise the contrast of label text on the dark background.

```css
.label {
  color: #c4c4cc;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid #34343c;
}
```

The new pair passes **WCAG AA** (4.6:1).|}

let yuk_19 =
  {|The page waits for every comment before it sends the first byte.

### Measurements

| Page | First byte | Full page |
| :--- | ---: | ---: |
| `/issue/YUK-1` | 82 ms | 140 ms |
| `/w/stress` | 96 ms | 310 ms |

Reproduce with:

```sh
for i in 1 2 3; do
  curl -s -o /dev/null -w '%{time_starttransfer}\n' http://localhost:8080/issue/YUK-1
done
```

---

Next: stream the comments with `Yuka.Await`, as in YUK-2.|}

let yuk_20 =
  {|Measure the emitted modules and remove what the page does not use.

```typescript
import { build } from "esbuild";

const result = await build({
  entryPoints: ["demo/client/main.js"],
  bundle: true,
  metafile: true,
  write: false,
});
for (const [file, info] of Object.entries(result.metafile.outputs)) {
  console.log(file, info.bytes);
}
```

Run `make size` to check the budget in `bench/size/budget.json`.|}

let yuk_25 =
  {|Summarize what v0.1 includes.

# Yuka v0.1

- Server pages with **islands**
- Client navigation and prefetch
- Forms that work with JavaScript off
- Live updates over a socket

## To do

- [x] Collect the changes from `CHANGES.md`
- [ ] Write the upgrade notes
- [ ] Publish on [opam](https://opam.ocaml.org)|}
