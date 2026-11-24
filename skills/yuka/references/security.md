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
  or `data:` URL (a dev build logs it once), and `Yuka.Browser.replace_url`
  does nothing with those or with a URL on another origin. A form follows only a
  `redirect` on this site (the request `Host`, or an origin of
  `Yuka.Server.config ~origins`): the server answers 500 and logs one that
  is not, and the browser refuses one from another origin and shows an
  error. The same check applies to a guard's `Redirect` stop; only
  `Redirect_off_site` leaves the site.
- A hand-written template (`Yuka.Private.template`, for tests) has its
  tags and fixed attributes checked as above.
- `<script>` and `<style>` take one text (the ppx joins the texts and
  values you write inside them) and nothing else, in any case and in any
  namespace. In HTML their text is printed as written, not HTML-escaped:
  every `</` gets a backslash after the `<`, and so does `<!--` in a
  JavaScript script; in a script of another type (JSON, import map), every
  `<` becomes `\u003c`. Inside `<svg>` and `<math>` (but not in an
  SVG `<foreignObject>`) they are ordinary elements and their text is
  escaped; so it is inside `<select>`, where an HTML parser can drop the
  start tag and read the text as markup.
- A page with no island ends with an inline
  `<script type="speculationrules">` (see "Prefetch" in
  [Router](router.md)). Yuka sends no `Content-Security-Policy`. An app
  that sets `script-src` must allow this element: add the hash of its
  text, `'sha256-noc9jWPkx7Sf6fj4Eowojtg1qcTXxDSHRgItGG0axUw='`. The hash
  works in every browser that runs the rule. It is the hash of the text of
  this release and changes when the text changes. In tests with Chromium
  151 and Chromium 156, `'inline-speculation-rules'` also allowed the
  element; other browsers and versions were not tested. Without either, the page
  works and has no prefetch, and each page with no island reports a CSP
  violation (in the console, and to `report-uri` or `report-to` when the
  policy has one).
- Sessions of `yuka-server` (`Yuka_server.sessions`) are signed cookies
  with no store: one session cannot be ended before it expires, so a
  stolen cookie is valid until then (14 days by default). Each use in the
  second half of that time gives a new cookie for the same session, so a
  thief who uses the cookie keeps the session until its absolute limit,
  `~max_lifetime` (30 days from its start by default). Anyone who has
  the secret can make a valid cookie: keep it out of the source code. Set
  `~secure:true` on HTTPS: without it the cookie has no `Secure` and no
  `__Host-` name, so a page on another subdomain can set its own valid
  cookie for the site. A page that reads the session under a shared cache
  rule (`public`, `s-maxage`) puts a `set-cookie` on a cacheable answer.
- `yuka-server` limits the time to send a request head (10 seconds) and
  the time a connection waits for a next request (60 seconds), but not
  the time to send a body and not the number of connections. Put a proxy
  in front of a public server.
