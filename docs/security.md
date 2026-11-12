# Security

- Text and attribute values are HTML-escaped on the server.
- URL attributes (`href`, `src`, `action`, `formaction`, `poster`,
  `xlink:href` and the like, in any case, and `values`, `to`, `from`, `by`
  of SVG animations) are read as the browser reads them (case, leading
  spaces and control characters, tabs and newlines). A `javascript:` or
  `vbscript:` URL is printed and set as `about:blank#blocked`, like React
  does; so is a `data:` URL where it would open or load a document or a
  script (links, forms, frames, `object`, `embed`, `script`, SVG `use`). A
  `data:` image or media URL is kept. A dev build logs the first block; a
  literal one in `.mlx` does not build. There is no way around it: use an
  event handler. In the browser the check runs where the attribute is set,
  with the real element, so it gives what the server prints.
- `srcdoc` of `iframe` is HTML, and `href` of `base` changes where every
  relative URL of the page points: a value that is not a literal in `.mlx`
  is printed and set as the empty string. Write them in `.mlx`, or point
  `src` at a page.
- `src` of `script` loads code: Yuka checks its scheme only. Never build it
  from user input. The same goes for the `content` of
  `<meta http-equiv="refresh">`: browsers do not follow a script URL there,
  but it can send the page to any other site.
- A tag name must be a letter followed by letters, digits and `-`;
  anything else raises an exception (in the browser, the DOM refuses it).
- An attribute name that is empty, starts with `on` (any case), or has a
  space, a control character, `"`, `'`, `<`, `>`, `/` or `=` raises an
  exception. Event handlers are functions: `on_click=(fun event -> ...)`
  in `.mlx` or `Yuka.on`; a string handler in `.mlx` does not build.
- `Yuka.Browser.navigate` does nothing with a `javascript:`, `vbscript:`
  or `data:` URL (a dev build logs it once). A form follows only a
  `redirect` on this site (the request `Host`, or an origin of
  `Yuka.Server.config ~origins`): the server answers 500 and logs one that
  is not, and the browser refuses one from another origin and shows an
  error. The same check applies to a guard's `Redirect` stop; only
  `Redirect_off_site` leaves the site.
- Hand-written templates go through `Yuka.template_of_shape`, which checks
  their tags and fixed attributes as above.
- `<script>` and `<style>` take one text (the ppx joins the texts and
  values you write inside them) and nothing else, in any case and in any
  namespace. In HTML their text is printed as written, not HTML-escaped:
  every `</` gets a backslash after the `<`, and so does `<!--` in a
  JavaScript script; in a script of another type (JSON, import map), every
  `<` becomes `\u003c`. Inside `<svg>` and `<math>` (but not in an
  SVG `<foreignObject>`) they are ordinary elements and their text is
  escaped; so it is inside `<select>`, where an HTML parser can drop the
  start tag and read the text as markup.
