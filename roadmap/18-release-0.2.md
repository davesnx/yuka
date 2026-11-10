# Release 0.2

Type: wayfinder:task
Release: 0.2
Blocked by: 05, 06, 07, 09, 11, 16, 17, 19
Claimed by: none

## Question

Build: `CHANGES.md` has a 0.2 section for `yuka` and `yuka-dream`. A `dune-release` dry run passes. Both packages install from a clean opam switch, and the README example builds against the installed packages. The user pushes the tag.

## Notes

Prepared: `CHANGES.md` has `## 0.2 (YYYY-MM-DD)` with a `yuka` and a
`yuka-dream` part, and `release.yml` releases `yuka,yuka-dream` in one
`dune-release` run. The workflow's `dry_run` input is now passed to the
action. `Release` no longer starts on a tag push: it starts when CI passes
on a tag push, or by hand, so one tag gives one release run. The action
accepts only a `refs/tags/` ref, and under `workflow_run` the ref is the
default branch, so the step sets `TEST_OVERRIDE_GITHUB_REF` (the variable
that `dune-release-action` v0.4.0 reads first) to `refs/tags/<tag>`.

What the user does to release:

1. Replace `YYYY-MM-DD` in `CHANGES.md` with the date, and commit.
2. Tag `0.2`, not `0.2.0` and not `v0.2`: the action looks for the
   `CHANGES.md` heading that equals the tag.

   ```sh
   git tag -a 0.2 -m "Release 0.2"
   git push origin 0.2
   ```

3. The tag push runs CI. When CI passes, `Release` runs:
   `dune-release distrib`, a GitHub release, and one opam-repository pull
   request with `yuka.0.2` and `yuka-dream.0.2`. It needs the `GH_TOKEN`
   secret. If CI fails, nothing is released. To try it first without
   publishing, run `Release` by hand with tag `0.2` and `dry_run`
   checked.

Facts and follow-up:

- Lower bounds are the tested versions: OCaml 5.4, dune 3.16 (tested
  3.24.2), melange 7.0.1-54, ppxlib 0.38.0, dream 1.0.0~alpha8, lwt 6.1.2
  (no bound; `yuka-dream` uses only old `Lwt` functions and
  `Lwt_unix.sleep`). Untested: dream 1.0.0, older ppxlib, older lwt.
- `dune-release` was not installed here, so it did not run.
- The tests that run `node` (Melange DOM, registry, navigation, templates,
  routes client) need the npm packages `jsdom` and `esbuild`. They do
  not run in the release profile (`-p`, so opam), and run with
  `make test` and in CI.
- Follow-up: a `yuka-routes` option for the request type, so that a tree
  where no function takes the request needs no `routes_server.mli`.
