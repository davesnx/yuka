# utop demo

A fake utop, the OCaml toplevel, in a Zed window. Each file of the project
panel is a session written in advance; the prompt answers in the browser.
Nothing runs OCaml: the answers are data, in the words of OCaml 5.3.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/` and this demo at `/utop`, with the other
demos, in one process. To run this demo alone, at the root:

    make utop-serve PORT=8080

`server/utop_demo_server.exe` takes `--port`, `--interface`, `--base
PREFIX`, `--bundle` and `--dir`.

## How it works

- `Routes.ml` has one route, `/?file=NAME`. The page is the Zed window:
  the title bar, the project panel with a link for each session, the tabs
  and the status bar are server HTML.
- `shared/terminal.mlx` is the one island: the banner, the history of the
  session (a `Yuka.each` of phrases), the prompt and the completion bar.
  The prompt is a transparent `<input>` over the highlighted phrase, so the
  caret and the selection are the browser's.
- `shared/repl.ml` answers a phrase: a phrase of the session or of
  `Session.extra`, else integer arithmetic (`+ - * / mod`, parentheses,
  names from `let x = ...;;`; the prompt runs in the browser, so integers
  have 32 bits, not the 63 of OCaml), else an `Unbound value` error. Enter without
  `;;` continues the phrase on a new line, as utop does. Up and Down walk
  the history, Tab takes the first completion, Ctrl+L clears the screen
  and `#quit;;` stops the toplevel.
- `shared/highlight.ml` splits phrases and answers into tokens. The server
  and the browser run the same code, so the history looks the same before
  and after the island starts.
- `shared/session.ml` holds the sessions. A string literal with characters
  outside ASCII in shared code is written `{js|...|js}`, so Melange makes
  a JavaScript string of the characters, not of the UTF-8 bytes (the box
  of the banner and the bar above each prompt).

## Design

The page and the window come from [`../zed`](../zed/README.md), the design
system of the utop and top demos: the fonts, the colours and the icons of
Zed. `static/style.css` styles only the content of the window.

## Tests

    make demo-test

`test/run.ml` renders two sessions and checks the phrases, the island and
the selected file, and checks the answers of `Repl.evaluate`, completion
and the highlighter. `e2e/utop.ts` types in the browser; see
`e2e/README.md`.
