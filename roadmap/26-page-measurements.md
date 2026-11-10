# Page measurements: JavaScript, TBT and LCP

Type: wayfinder:task
Release: 0.3
Blocked by: none
Claimed by: none

## Question

Build: a repeatable check that measures, for each demo page, the JavaScript bytes sent, Total Blocking Time and LCP, and LCP of the same page as plain server HTML. A page with no island must send 0 bytes of JavaScript.

## Resolution

`make measure-pages` (`bench/pages/measure.ts`) bundles the demo, starts it with `--bundle`, and for each page (`/`, `/my`, `/issue/YUK-1`, `/about`) measures: JavaScript loaded without user input (each script and modulepreload response, raw and gzip -9, plus inline script bytes), Total Blocking Time and LCP (Chromium headless through Playwright, CPU throttle 4x, 5 runs, median; TBT is the sum of long task time over 50 ms after first contentful paint, until 2 s after network idle), and LCP of the same page with every `<script>` and modulepreload link removed. It prints a table and writes `$(BUILD_DIR)/measure-pages/result.json` with every run and the load average. Options: `PAGES_RUNS`, `PAGES_THROTTLE`, `CHROME_PATH`.

0-JS check: every measured page with no `<yuka-island>` must send 0 bytes of JavaScript; the command exits 1 otherwise, and also when no measured page is island-free. `/about` is the island-free test page in the demo.

First numbers (2026-11-10, Chromium 151, load average 111 -> 127):

| page | islands | JS files | JS raw | JS gzip | inline JS raw | TBT ms | LCP ms | plain HTML LCP ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `/` | 3 | 9 | 106591 | 32555 | 481 | 0 | 68 | 60 |
| `/my` | 3 | 9 | 106591 | 32555 | 481 | 0 | 52 | 52 |
| `/issue/YUK-1` | 5 | 10 | 103978 | 32333 | 513 | 0 | 60 | 56 |
| `/about` | 0 | 2 | 69045 | 22203 | 481 | 0 | 72 | 40 |

Targets:

- TBT 0: met on every page.
- LCP equal to plain HTML: within noise on `/`, `/my`, `/issue/YUK-1`; `/about` is 72 against 40 ms, on every run (56 to 80 against 36 to 48). LCP runs on the issue page range from 52 to 932 ms, because the streamed comments sometimes become the largest paint.
- 0 bytes of JavaScript without islands: FAILS. `/about` sends `main.js` and the shared chunk (69045 bytes) and the 481-byte inline fill script. Ticket 11 decision (J) (`routes-spec.md` 3.2) removes the module script from a response with no island; the fill script stays in the head of every streamed response, so the check still fails after (J) unless the fill script is also written only when a response has a pending await.
