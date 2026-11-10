# Navigation protocol

Type: wayfinder:grilling
Release: 0.3
Blocked by: 09
Claimed by: none

## Question

Does client navigation keep the full-body swap, or update only the changed part below the deepest shared layout?

## Resolution

Done (2026-11-10), increment 4 of `.workplace/docs/routes-spec.md` (section 4). A client navigation sends the keys of the page's `<yuka-outlet>` elements in `Yuka-Navigate`; the server answers the content of the deepest shared outlet with `Yuka-Outlet`, `Yuka-Title` and `Yuka-Build`, or a full document when no layout is shared. The client replaces only that outlet, so islands in shared layouts (the demo's sidebar `Counter` and `New_issue`) keep their state; it moves `aria-current` on links outside the outlet and outside islands, and loads the page in full when `Yuka-Build` differs from the page's `<meta name="yuka-build">`. Cost: the demo client grew by 531 B gzip; the keyed app by 4 B. Changes from the spec are in its section 8. Tests: `test/cycle` (navigation), `test/navigation`, `e2e/demo.ts` (3b, 3c, 3d).
