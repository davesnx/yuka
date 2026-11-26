# Quest demo

Ashfall, a story told by the server. Five acts of five riddles, then a
game of noughts and crosses against the Ash King. The page fills the
window, with a fullscreen button (or the F key) and the keys 1 to 9 for
the choices.

## Run

From the repository root:

    make demo-serve PORT=8080

serves the list of demos at `/` and this demo at `/quest`, with the other
demos, in one process. To run this demo alone, at the root:

    make quest-serve PORT=8080

`server/quest_server.exe` takes the flags of the Async server: `--port`,
`--interface`, `--base PREFIX`, `--bundle`, `--dir` and `--secret`. With `--tree` it
prints the tree of scenes and exits (`make quest-tree`).

## How it works

- `server/story.ml` builds the tree of scenes when the server starts. The
  root is the opening, then each act has a title scene and five riddles.
  A riddle has one child per answer: the right one leads on, a wrong one
  to a death, a leaf whose exits go back up to the riddle or to the start.
  After the last riddle comes the duel: a subtree with a child for each
  free cell, the cell the player takes and the reply of the King. The
  King wins when he can, blocks when he must, and else takes the centre,
  a corner, then a side, so a fork beats him.
- `Routes.ml` has two routes: `/`, the opening, and `/scene/:id`. The id
  is the first 12 hex digits of a digest of the place of the scene in the
  tree, so a URL says nothing about where it leads, and the same scene
  has the same URL after a restart. Each scene is a page: Back, Forward,
  reload and a shared link work. An unknown id is a 404.
- The server streams each scene: the banner and the board come first,
  then each line of the tale is a `Yuka.Await` with `blocking=`No` that
  the server fills 0.45 s after the one before, and the exits come last.
  The tests set `Pages.step` to 0.
- The layout (`Pages.shell`) holds the background, the embers and the
  `Hud` island: the fullscreen button, the F key, and a rune that turns
  while `Yuka.Browser.navigating` is true. As the layout stays, a client
  navigation replaces only the scene. The `Hotkeys` island on each scene
  gets the URLs of its exits and navigates on the keys 1 to 9.
- `shared/fullscreen.melange.ml` calls the Fullscreen API;
  `fullscreen.ml` is the native side, which does nothing.
- The look is CSS only (`static/style.css`): stone panels with bronze
  rims, gold titles, a life globe and a mana globe (the share of riddles
  solved), and a belt of 25 pips, one per riddle.

## Tests

    make demo-test

`test/run.ml` checks the shape of the tree (25 riddles, two deaths each,
the duel at the end), renders the opening, each riddle with a link to
each answer, a death with its link back up, and a won duel.
`e2e/quest.ts` plays the story in a browser.
