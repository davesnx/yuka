# SSR throughput

Requests per second and p50/p99 latency for one page, rendered by Yuka and by
reference candidates, on the same machine. Ticket 27 chooses the reference;
this benchmark only measures.

## Page

`GET` an HTML document with a list of N issues (default 100). Each row is an
`<li>` with a link, id, title, status, priority, assignee and 0 to 2 labels.
The titles contain `"`, `&`, `<` and `>`, so each candidate escapes text. The
data is built once at start; each request renders the whole page again. The
server checks that the page has N rows before it measures. No islands, no
hydration data.

| candidate | how it renders | server |
| --- | --- | --- |
| `dream-concat` | `Buffer` and hand escaping (the floor) | Dream |
| `yuka-page` | `Yuka.Server.document` of mlx components | Dream |
| `yuka-stream` | `Yuka.Server.stream`, as the demo answers (adds the fill script) | Dream `stream` |
| `server-reason-react` | `ReactDOM.renderToString` | Dream |
| `react-node` | React 19 `renderToString`, `NODE_ENV=production` | `node:http` |
| `solid-node` | Solid 1.9 `renderToString`, babel-preset-solid `generate: "ssr"` | `node:http` |

Each server is one process with one thread of JavaScript or OCaml. Sources:
`ocaml/` and `node/`.

## Run

    make bench-ssr SWITCH=<opam switch>

It builds `ocaml/` with `--profile=release`, runs `npm ci` in `node/` once,
then `node bench/ssr/run.ts`. For each candidate: start the server, 5 s of
`wrk` warm-up, 3 rounds of `wrk -t4 -c32 -d10s --latency`, report the median.
Options of `run.ts`: `--rows`, `--connections`, `--threads`, `--duration`,
`--warmup`, `--rounds`, `--only <names>`, `--out`. Make variables: `SSR_ROWS`,
`SSR_CONNECTIONS`. The JSON goes to `$(BUILD_DIR)/bench-ssr/result.json`,
with each round and the load average at its end.

Needs `wrk` on the `PATH`. `server-reason-react` is skipped when the opam
switch does not have it.

## First numbers

2026-11-10, 512 cores, shared machine. `uptime` before: load average 85.65,
95.82, 109.54; after: 44.83, 70.81, 96.89. 100 rows, `wrk -t4 -c32 -d10s`, 3
rounds, median.

| candidate | bytes | req/s | p50 ms | p99 ms | vs floor | spread of the 3 rounds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| dream-concat | 36935 | 13696 | 2.29 | 4.32 | 1.00 | 4% |
| yuka-page | 35935 | 3832 | 8.12 | 15.80 | 0.28 | 2% |
| yuka-stream | 36433 | 4163 | 7.56 | 14.49 | 0.30 | 2% |
| server-reason-react | 36939 | 6380 | 5.08 | 9.70 | 0.47 | 2% |
| react-node | 36937 | 3197 | 9.85 | 15.31 | 0.23 | 1% |
| solid-node | 35635 | 7689 | 4.06 | 8.10 | 0.56 | 3% |

Noise: the rounds of one candidate differ by 1% to 4%. The load average fell
from 77 to 45 during the run, and the candidates ran one after the other, so
a difference under about 10% between two candidates is not a result. A
second run 10 minutes later (load average 62 -> 43) gave req/s within 4% of
these for each candidate: 13631, 3885, 4157, 6575, 3262, 7967.
