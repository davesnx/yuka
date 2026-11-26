# Zed design

The design system of the [utop](../utop/README.md) and
[top](../top/README.md) demos: a page in the style of
[zed.dev](https://zed.dev) around a Zed window.

- `static/zed.css`: IBM Plex Serif for titles, IBM Plex Sans for text,
  Lilex for code (Zed's default fonts), the brand blue `#1348dc`, and the
  One Dark and One Light themes of Zed (`assets/themes/one/one.json` in
  the Zed repository), chosen by `prefers-color-scheme`. It styles the
  page, the window (title bar, panel, tabs, status bar), the icons, the
  buttons and the keys under the window.
- `static/icons/`: icons of Zed (`assets/icons/`, Lucide based, ISC
  license in `static/icons/LICENSES`), drawn with the text colour by a CSS
  mask: `Zed_ui.icon "server"` is `<span class="icon icon-server">`.
- `static/fonts/`: the fonts, under the SIL Open Font License
  (`OFL-*.txt`).
- `ui/zed_ui.mlx`: the window and its parts (`window`, `row`, `folder`,
  `tab`, `status`), the page (`page`, `keys`, `not_found`) and `icon`, for
  native and Melange, so an island can use the icons too.

A demo serves the files with `Zed_ui.public ~dir`, which maps `/zed` to
`../zed/static` next to the directory of the demo, and loads
`Zed_ui.stylesheet base` before its own `static/style.css`. To add an
icon, copy it from `assets/icons/` of the Zed repository to
`static/icons/` and add its `.icon-NAME` line to `zed.css`.
