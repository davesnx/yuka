# Original notes (verbatim)

# Why

### Take advantage of OCaml

- Advantage of the type system
    - is there any way to ensure key args are present in List stuff? anyway to not even need those?
    - can we have type-safe children? Button only accepts Text nodes kind of rules?
    - any way to remove the hook order?
    - Suspense could catch errors and be type-safe
    - Safety around attributes
    - Minimum safety ala tyxml (same errors as react I would say)
- Take advantage of the effect system
    - Effects as ppx https://x.com/javierwchavarri/status/1079588586507378689
    - https://github.com/reduxjs/redux/issues/455
    - https://github.com/reduxjs/redux/issues/1528
    - why this effect runs (create monads? use eio model?)
    - a way to compose effects
    - somehow relate effects and renders
    - https://www.npmjs.com/package/derivable
- Better integration with Melange
- Focused in universal code from the start

### Simplify model of React

- Challenge some ideas from React
    - remove rules of hooks
    - remove need for compiler (melange does all hard work or ppx does)
    - props
- Embrace elm/ui and elm/html patterns
- Embrace mobx?
- Check preact v11 implementation
- Study incremental from janestreet
    - https://github.com/let-def/lwd
- study async react
    - Fiber
    - non-blocking vs blocking
    - (useDeferredValue, useOptimistic)
    - setState vs dispatch multiple rerenders
- Lazy from Elm https://jfmengels.net/caching-behind-elm-lazy/ https://jfmengels.net/beyond-elm-lazy-arguments/ https://jfmengels.net/make-your-roots-lazy
- Server ↔ Client resumability possible? https://brumate-docs.vercel.app/
- Implement hooks?
    - https://www.deepintodev.com/blog/how-to-create-your-own-simple-use-state-hook
- https://romgrk.com/posts/reactivity-is-easy

### Build your own react

- https://pomb.us/build-your-own-react
- https://github.com/retrogtx/unreacted
- https://www.rob.directory/blog/react-from-scratch
- https://github.com/tigerabrodi/arwaal/
- https://tchayen.com/understanding-react-by-implementing-it
- https://github.com/JoeS51/React-lite/blob/main/ReactLite.js
- https://geekpaul.medium.com/lets-build-a-react-from-scratch-part-1-virtualdom-and-renderer-14f4f716de62

https://romgrk.com/posts/react-functional-components

https://github.com/jsdotlua/react-lua

---

- https://github.com/frejs/fre
- preact
- https://github.com/lpalmes/pure
- https://github.com/briskml/brisk-reconciler
- https://github.com/jorgebucaran/superfine
- https://vanjs.org
- https://x.com/_developit/status/905250269306474497
- https://cycle.js.org/components.html
- https://day8.github.io/re-frame/application-state
- https://github.com/joshburgess/tachys

---

```reason
module State = struct
    type 'value t = 'value
    let make value = value
end

let (a, setA) = State.make(0);

State.get(a) -> gets the value

Effect.xxx ~equal=??? ();

Effect.xxx a (fun (prevA nextA) -> ...)

Effect.xxx a (fun (a) -> ...)

Effect.xxx a (fun (a) -> ...)
```
