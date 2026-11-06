# Finger trees (Hinze & Paterson) and Yuka

## Sources

- https://www.staff.city.ac.uk/~ross/papers/FingerTree.pdf — read (all 21 pages). Downloaded, then text extracted with a small stdlib script; ligatures "fi"/"fl" were lost in extraction, so quotes below are paraphrased.
- https://raw.githubusercontent.com/ocaml-batteries-team/batteries-included/master/src/batFingerTree.mli — read through a summarising fetch tool, not line by line.

## What the paper says

- **Shape (§3, §3.1).** Start from a 2-3 tree with all leaves at the same depth. Lift the two end leaves up: you get a central spine. Each spine level holds a left and right *digit* (a buffer of 1–4 elements) and a middle finger tree whose elements are 2-3 *nodes* one level deeper. The type is nested (non-regular): `FingerTree a = Empty | Single a | Deep (Digit a) (FingerTree (Node a)) (Digit a)`. An element `d` positions from the nearest end sits at depth O(log d).
- **Deque ends (§3.2).** `cons`/`snoc` push into a digit; only when a digit holds 4 do three elements move down as a `Node3`. Digits of 2–3 are "safe", 1 or 4 "dangerous"; a push or pop propagates down only from a dangerous digit and leaves it safe. So the average cost is O(1) amortised; worst case O(log n).
- **Laziness and persistence (§3.2).** The amortised bound also holds when old versions are reused (persistent use), but only if the middle subtree of each `Deep` node is a suspension. Okasaki's debit argument: each suspension carries as many debits as safe digits; each operation discharges at most one. In a strict language, suspend only the middle subtree (O(log n) suspensions per tree).
- **Concatenation (§3.3).** `app3` merges the two trees' inner digits into nodes and recurses down the shallower spine: O(log (min n1 n2)).
- **Annotations (§4.1–4.3).** Each node caches a *measure*: a reduction of its contents with a monoid (`Measured a v` maps an element to `v`; `v` is a monoid). Smart constructors `node2`, `node3`, `deep` recompute the cached value from the children. Digits are measured on the fly (bounded size). The tree is nested in `a` but regular in `v`.
- **Split by predicate (§4.4).** `splitTree p i t` finds the point where a predicate on the accumulated measure (a left-to-right scan) flips from false to true, skipping whole subtrees using their cached measure. Cost O(log (min nl nr)). The split is unique when `p` is monotonic.
- **Applications (§4.5–4.8).** One generic split gives many structures, chosen by the monoid:
  - `Size` (+): random-access sequence; `length` O(1), `splitAt`/index O(log n).
  - `Prio` (max): max-priority queue; `extractMax` by split.
  - `Key` (last key): ordered sequence; partition, insert, delete, and an adaptive merge in O(m log (n/m)).
  - product of `Key` and `Prio`: interval tree; find one overlap in O(log n), all m in O(m log (n/m)).
- **Performance (§5, Table 1).** Competitive with specialised persistent deques; as search trees 3–5 times slower than good balanced binary trees. Ephemeral (mutable) structures are usually faster.

## Where it touches Yuka

Checked against `DECISIONS.md` and the discussion so far.

| Yuka topic | What the paper's idea would change | Real gap or internal choice | Cost |
|---|---|---|---|
| Keyed lists (`each ~key`) | Today `each` takes a plain OCaml list from a getter. Every change means scanning the whole list to diff keys: O(n), even for one insert. A persistent sequence annotated with (size, key) could let a collection state report *what* changed (insert at i, remove range, move) and let `each` patch in O(k log n). | **Real gap, not about finger trees specifically.** We have no collection story: what type `each` and `State.memo` accept, and whether changes arrive as whole values or as edits. Bonsai solves this with `Map` plus diffing (`assoc`); a finger tree is another candidate. The DOM move step (keyed diff, LIS as in Preact 11) is unaffected: the paper does not give a list-diff algorithm. | A collection type in the public API. O(log n) per element op instead of O(1) list cons. |
| Incremental aggregates (`State.memo` over a collection) | `State.memo (fun () -> total (items ()))` recomputes over all items on any change. Cached monoid measures in tree nodes give the aggregate in O(1) and keep it current in O(log n) per edit. This is the paper's main idea: a memo per subtree, with the monoid as the combining rule. | **Real gap for large collections**, same root as the row above. For small lists, plain `State.memo` is fine. | Users must express the aggregate as a monoid (`zero`, associative `combine`). |
| Virtualised lists | Measure = cumulative row height. "Which row is at scroll offset y" is `splitTree (> y)`: O(log n). Total height is the root measure: O(1). Changing one row's height updates O(log n) cached sums. | **Internal / library choice.** A `Virtual_list` component could use it. Not a core design gap. | Row heights must be known or measured; layout reads are a separate problem. |
| Default equality (open) | Persistent structures share unchanged parts, so "unchanged" is physical equality, and it is cheap. Blocks have the same identity on native and Melange; the earlier divergence was only for strings, floats and int64. | **Input to the open decision, not a gap.** It argues for `==` on structured, persistent state, with typed overrides for strings, floats, int64. | None by itself. |
| Effect and propagation order | The `Key` ordered sequence supports insert and delete by key in O(log n). One could keep effects in tree order with it. | **Real gap, but the paper is not the right tool.** We never defined the order in which derived values and effects run after a `set` (glitch freedom, parent before child, creation order). The scratch test ran effects in reverse creation order. Incremental's answer is node heights plus a queue by height (`reactivity.md`, marked memory). Keys for "tree position" need an order-maintenance scheme, which the paper does not give. | Design work on the propagation algorithm. |
| Scheduler with lanes | Max-priority queue by split. | **Not needed.** A scheduler holds few tasks and a few priorities; a list or a binary heap per lane is enough and faster. | — |
| Transitions (committed vs pending state) | Persistence: old versions stay valid and share structure, so keeping two versions is two pointers. | **Not a gap from this paper.** OCaml values held in `State` are already immutable, so this already holds for the values. The hard part is the derived graph, which the paper does not address. | — |
| State getter/setter, `Effect.on_change` prev/next, Async, cancellation scopes, render once, server-to-client resume, streaming | — | **No relation.** The paper is about sequence representation. | — |

### OCaml specifics

- **Nested type.** OCaml accepts the non-regular type directly: `type 'a t = Empty | Single of 'a | Deep of 'a digit * 'a node t * 'a digit`. Functions over it recurse at a different type (`'a node t`), so they need polymorphic recursion with an explicit annotation: `let rec cons : 'a. 'a -> 'a t -> 'a t = ...`. The measure type `'m` stays fixed across levels ("regular in v"), so it can be a parameter of the type or of a functor.
- **No type classes.** `Measured` becomes an explicit argument: a monoid record (`zero`, `combine`) plus a measure function, or a functor. Batteries' `BatFingerTree` uses the record form (`type 'a monoid = { zero; combine }`) and exposes generic `split` and `lookup` by predicate, `append` in O(log (min n m)), and a `Sequence` module with O(1) `size` and O(log n) `get`/`set`/`split_at`. Its docs say "O(1) amortized, O(log(n)) worst case" for the ends; whether it suspends the middle tree was not stated in what I read.
- **Melange.** GADTs and polymorphic recursion compile on Melange (checked earlier in this project for GADTs; polymorphic recursion not separately checked). Batteries as a whole is not a Melange library (memory: it depends on `Unix` and native-only modules). A Yuka collection would need its own implementation or a vendored copy of one module. The paper's code is about 300 lines with the `Digit` variant of Exercise 1.
- **Laziness.** OCaml is strict. Without suspending the middle subtree, the O(1) amortised bound holds only for single-threaded use. If an old version is reused (for example an effect's `prev` value, or a pending and committed copy), an expensive cascade can repeat, so each end operation is O(log n) in the worst case. That is still acceptable for UI sizes. `Lazy.t` exists in OCaml; on Melange `lazy` is supported (memory, not checked here).

## Verdict

1. **Real gap: no collection model.** `each` and `State.memo` work on whole plain lists, so every change costs O(n) to diff and to re-aggregate. Decide what a collection state is (plain list, `Map` with diffs as in Bonsai, or an annotated persistent sequence) and whether changes reach `each` as values or as edits. A finger tree is one candidate, not the only one.
2. **Real gap the paper only points at: propagation and effect order.** After a `set`, the order of recomputation and effect runs is undefined in our design (and the scratch test ran effects in reverse). Use heights and a queue as Incremental does; the paper's ordered sequence is not the tool.
3. **Input to the open "default equality" decision.** Persistent data makes `==` a cheap and reliable "unchanged" test for structures on both targets; the cross-target problems are limited to strings, floats and int64.
4. **Later, library level: virtualised lists** can use a height-measured tree for O(log n) offset lookup.
5. **Not needed:** a finger-tree priority queue for the scheduler; anything about State's API shape, Async, cancellation, serialisation, resume or streaming.
6. **If adopted:** write or vendor a small strict implementation for Melange; accept O(log n) worst-case ends instead of adding laziness, unless measurements show otherwise.
