# JavaScript + Bash + PowerShell Knowledge Test Suite — Answers

---

## Section 1: JavaScript / TypeScript (JS1–JS20)

### JS1 — Easy
**Answer:**
- `var`: function-scoped (or global), hoisted to the top of the enclosing function with initial value `undefined`, can be redeclared and reassigned. Attaches to the global object when declared at top level in scripts.
- `let`: block-scoped (`{}`), hoisted but not initialized — references before the declaration throw a `ReferenceError` (the "temporal dead zone", TDZ). Can be reassigned, not redeclared in the same scope.
- `const`: block-scoped, also in TDZ until declaration, must be initialized at declaration, the binding cannot be reassigned. Note that objects/arrays bound with `const` are still mutable — only the binding is immutable.

**Hoisting**: the JS engine processes declarations before executing code in a scope. `var` declarations and `function` declarations are hoisted and initialized (functions get their full value, `var` gets `undefined`). `let`/`const`/`class` are hoisted but uninitialized — accessing them before their declaration throws `ReferenceError` due to the TDZ.

### JS2 — Easy
**Answer:**
JavaScript runs on a single thread with an **event loop** that coordinates execution between:

- **Call stack**: LIFO stack of function frames being executed synchronously. JS can only do one thing at a time on the stack.
- **Macrotask queue** (task queue): contains tasks like `setTimeout`/`setInterval` callbacks, I/O, `setImmediate` (Node), MessageChannel, UI events.
- **Microtask queue**: contains Promise `.then`/`.catch`/`.finally` callbacks, `queueMicrotask`, and `MutationObserver` callbacks (browser).

Loop algorithm: when the call stack is empty, the event loop picks **one** macrotask, runs it to completion on the stack, then **drains the entire microtask queue** (any microtasks scheduled while draining also run before yielding). Then (in browsers) it may render, then pick the next macrotask. This is why microtasks can starve macrotasks if they keep enqueueing more microtasks.

```js
console.log('A');
setTimeout(() => console.log('B'), 0);
Promise.resolve().then(() => console.log('C'));
console.log('D');
// A, D, C, B — microtask (C) runs before macrotask (B)
```

### JS3 — Medium
**Answer:**
A **closure** is a function together with the lexical environment in which it was created — it "closes over" variables from its enclosing scope and can access them even after that scope has returned.

Practical example — a counter factory:
```js
function makeCounter() {
  let count = 0;
  return {
    inc: () => ++count,
    get: () => count,
  };
}
const c = makeCounter();
c.inc(); c.inc();
console.log(c.get()); // 2
```

**Classic `for` loop closure bug** (pre-`let`):
```js
for (var i = 0; i < 3; i++) {
  setTimeout(() => console.log(i), 0);
}
// Prints 3, 3, 3 — all closures share the same `i` (function-scoped var)
```

Fixes:
1. Use `let` (block-scoped — each iteration gets a fresh binding):
   ```js
   for (let i = 0; i < 3; i++) setTimeout(() => console.log(i), 0); // 0,1,2
   ```
2. IIFE to capture per iteration:
   ```js
   for (var i = 0; i < 3; i++) {
     (function (j) { setTimeout(() => console.log(j), 0); })(i);
   }
   ```
3. `.forEach` which gives each iteration its own parameter.

### JS4 — Medium
**Answer:**
A **Promise** represents an eventual value with states `pending → fulfilled | rejected`. You attach handlers via `.then(onFulfilled, onRejected)`, `.catch`, `.finally`.

**async/await** is syntactic sugar: an `async` function always returns a Promise; `await p` pauses execution until `p` settles, resuming with the fulfilled value or throwing the rejection reason.

**Error handling**:
- Promises: `.catch(err => ...)` or second argument to `.then`. Unhandled rejections emit `unhandledrejection`/`process.on('unhandledRejection')`.
- async/await: `try/catch` around `await`. A thrown error inside an `async` function rejects its returned Promise.

```js
async function load() {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.json();
  } catch (err) {
    console.error(err);
    throw err;
  }
}
```

**`Promise.all(iter)`** — fulfills with an array of values once **all** fulfill; rejects as soon as **any one** rejects (fail-fast; other promises keep running but their results are discarded).

**`Promise.allSettled(iter)`** — always fulfills once **all** settle, with an array of `{status: 'fulfilled', value}` or `{status: 'rejected', reason}` objects. Use when you want every result regardless of individual failures.

Also: `Promise.race` (first to settle wins) and `Promise.any` (first fulfilled, rejects with `AggregateError` only if all reject).

### JS5 — Medium
**Answer:**
**`interface`**:
- Describes object shapes (and function/constructor signatures).
- Supports **declaration merging** — two `interface Foo` declarations in the same scope combine.
- Can `extends` other interfaces/classes.
- Preferred for public API shapes and for extensibility.

**`type`** (type alias):
- Can name *any* type — primitives, unions, intersections, tuples, mapped types, conditional types, template literal types.
- Cannot be re-opened / merged.
- Use for unions, tuples, complex type math.

Rule of thumb: use `interface` for object shapes that may be extended; use `type` for unions, intersections, and type manipulation.

**Discriminated unions** (tagged unions) — a union of object types that share a common literal "discriminant" property:
```ts
type Shape =
  | { kind: 'circle'; r: number }
  | { kind: 'square'; side: number }
  | { kind: 'rect'; w: number; h: number };

function area(s: Shape): number {
  switch (s.kind) {
    case 'circle': return Math.PI * s.r ** 2;
    case 'square': return s.side ** 2;
    case 'rect':   return s.w * s.h;
    default: {
      const _exhaustive: never = s; // exhaustiveness check
      return _exhaustive;
    }
  }
}
```
TypeScript narrows `s` inside each branch based on `s.kind`.

### JS6 — Medium
**Answer:**
Every JS object has an internal `[[Prototype]]` (accessible via `Object.getPrototypeOf(obj)` or the legacy `__proto__`). Property lookups walk the prototype chain until found or `null`.

**`Object.create(proto, props?)`** creates a new object whose `[[Prototype]]` is `proto`:
```js
const animal = { speak() { console.log(`${this.name} speaks`); } };
const dog = Object.create(animal);
dog.name = 'Rex';
dog.speak(); // Rex speaks
```

**ES6 classes** are syntactic sugar over prototype-based inheritance:
```js
class Animal {
  constructor(name) { this.name = name; }
  speak() { console.log(`${this.name} speaks`); }
}
class Dog extends Animal {
  bark() { console.log('woof'); }
}
```
Under the hood: `Dog.prototype.__proto__ === Animal.prototype`, instance methods live on `Class.prototype`, `static` methods live on the constructor itself, and `extends` wires up both the prototype chain of instances (for methods) and of constructors (for statics). `super(...)` calls the parent constructor, which must run before `this` is accessible in a derived constructor.

### JS7 — Hard
**Answer:**
`this` is determined at *call time* (for regular functions) by how the function is invoked, not where it was defined. The four binding rules in **priority order**:

1. **`new` binding** — `new Foo(...)` creates a fresh object, sets `this` to it, runs `Foo` with that `this`, and returns it (unless `Foo` returns a different object).
2. **Explicit binding** — `fn.call(ctx, ...)`, `fn.apply(ctx, args)`, `fn.bind(ctx)` force `this = ctx`.
3. **Implicit binding** — called as a method: `obj.fn()` → `this = obj`. Beware: `const f = obj.fn; f()` loses the binding.
4. **Default binding** — standalone call `fn()`. In strict mode `this = undefined`; in sloppy mode `this = globalThis`.

**Arrow functions** are an exception: they do *not* have their own `this`; they lexically capture `this` from the enclosing scope. `call`/`apply`/`bind` cannot change their `this`.

**`fn.bind(ctx, ...args)`** returns a new ("bound") function with `this` permanently pinned to `ctx` and optional partially applied `args`. **Re-binding a bound function has no effect on `this`** — calling `boundFn.bind(other)` or `boundFn.call(other)` still uses the original `ctx`. However `new boundFn(...)` ignores the bound `this` (rule 1 wins) and creates a new instance.

### JS8 — Hard
**Answer:**
**`WeakRef`** holds a weak reference to an object — the GC can still collect the target. `ref.deref()` returns the target or `undefined` if collected. Use sparingly; the spec intentionally gives no guarantees about *when* collection happens.

**`FinalizationRegistry`** lets you register a cleanup callback fired *sometime after* an object is garbage collected:
```js
const registry = new FinalizationRegistry((heldValue) => {
  console.log('cleaning up', heldValue);
});
registry.register(someObject, 'label', someObject);
```
Typical uses: releasing external resources (file handles, WASM memory) tied to JS objects, cache invalidation. Do not rely on finalizers for correctness — they may never run (e.g., at process exit).

**`WeakMap` / `WeakSet`**: keys/values must be objects (or, since ES2023, non-registered Symbols) because the implementation uses the key's identity and holds it *weakly* — if the key is otherwise unreachable, the entry is eligible for GC. Primitives like numbers have no identity ("is 42 still reachable?" makes no sense), so they can't be weak keys. This makes `WeakMap` perfect for attaching private data to objects without preventing their collection. Unlike `Map`, `WeakMap` is not enumerable and has no `.size` — that would expose GC timing.

### JS9 — Hard
**Answer:**
V8 uses a tiered pipeline: **Ignition** (bytecode interpreter) → **Sparkplug** (baseline JIT) → **Maglev** (mid-tier) → **TurboFan** (optimizing JIT). Hot functions are recompiled with speculative optimizations based on observed types.

**Hidden classes (Maps/Shapes)**: V8 assigns each object a hidden class describing its property layout (offsets). Objects created with the same sequence of property additions share a hidden class, enabling O(1) field access. *Tip: initialize all properties in the constructor in the same order — don't add/delete properties later.*

**Inline caches (ICs)**: at each property-access site, V8 caches the hidden class(es) it has seen and the offset for that class. Monomorphic sites (one class) are fastest; polymorphic (2–4 classes) still fast; **megamorphic** (>4) fall back to generic lookup.

**Deoptimization ("deopt")**: when a speculatively optimized assumption fails, TurboFan bails out to the interpreter and re-profiles. Common causes:
- Changing an object's shape after the fact (adding/deleting properties, changing types).
- Mixing types into a function that V8 had specialized for one type (e.g., sometimes passing an int, sometimes a string).
- Mutating array element kinds (e.g., turning a packed SMI array into a holey/double/tagged array).
- `arguments` leakage, `with`, `eval`, non-strict `delete`.
- Using `try/catch` (historically deopt-triggering, now mostly fine with TurboFan).

Write "monomorphic, type-stable, shape-stable" code; prefer `class`es and avoid late property additions.

### JS10 — Medium
**Answer:**
**Tree-shaking** is dead-code elimination performed by a bundler (Rollup, webpack, esbuild) that statically analyzes imports/exports and drops unused exports from the output bundle.

It works with **ES modules** because `import`/`export` is **static** — the set of imports is known at parse time without executing the code. The bundler can build an import graph, mark used exports as "live", and drop the rest. Pure-function annotations (`/*#__PURE__*/`) and `"sideEffects": false` in `package.json` help the bundler remove entire modules that would otherwise be retained for side effects.

**CommonJS** uses `require()` and `module.exports`, which are *dynamic*: `require` is a normal function call that can appear anywhere (inside conditions, inside functions), be computed (`require(name)`), and `module.exports` can be mutated arbitrarily at runtime. The bundler cannot statically determine which properties of `module.exports` are used, so it must conservatively keep everything. That's why CJS modules generally can't be tree-shaken — bundlers include the whole module even if you only use one export.

### JS11 — Easy
**Answer:**
- **`undefined`**: a variable has been declared but not assigned, a missing function argument, a missing object property, or the default return value of a function.
- **`null`**: an intentional "no value" assigned by the programmer.

**Equality**:
- `==` (loose): `null == undefined` is `true`, and they equal *only* each other (not `0`, `''`, `false`). `null == 0` is `false`.
- `===` (strict): `null === undefined` is `false` — different types.

**Nullish coalescing `??`**: returns the right operand only if the left is `null` or `undefined`. Unlike `||`, it does *not* fall through for other falsy values like `0`, `''`, `false`.
```js
const port = input ?? 8080; // keeps 0 if input === 0
```

**Optional chaining `?.`**: short-circuits to `undefined` if the value before it is `null`/`undefined`, otherwise continues the access:
```js
user?.profile?.name        // safe property access
arr?.[0]                   // safe index
fn?.()                     // safe call
```
Combine with `??` for safe defaults: `user?.name ?? 'anon'`.

### JS12 — Easy
**Answer:**
All three are non-mutating higher-order array methods:

- **`arr.map(fn)`** — returns a new array of the same length with each element replaced by `fn(el, i, arr)`.
  ```js
  [1,2,3].map(x => x * 2); // [2,4,6]
  ```

- **`arr.filter(fn)`** — returns a new array containing elements for which `fn` returns truthy.
  ```js
  [1,2,3,4].filter(x => x % 2 === 0); // [2,4]
  ```

- **`arr.reduce(fn, init?)`** — folds the array into a single value. `fn(acc, el, i, arr)` is called for each element, and its return value becomes the next `acc`. If `init` is provided, iteration starts at index 0 with `acc = init`; if omitted, `acc` starts as `arr[0]` and iteration starts at index 1 (and throws on an empty array with no init). **Always pass an initial value** — it's clearer and prevents the empty-array trap.
  ```js
  [1,2,3,4].reduce((acc, x) => acc + x, 0); // 10
  ```

- **`arr.flatMap(fn)`** — equivalent to `arr.map(fn).flat(1)`: map each element to an array (or single value) then flatten one level. Useful when a mapping may produce zero, one, or many outputs per input:
  ```js
  ['hi there', 'yo'].flatMap(s => s.split(' ')); // ['hi','there','yo']
  ```

### JS13 — Easy
**Answer:**
**Template literals** are strings enclosed in backticks that support multi-line content and `${expression}` interpolation:
```js
const name = 'world';
const msg = `hello, ${name}!
next line`;
```

**Tagged templates** let you intercept the parts of a template literal with a function:
```js
tag`Hello, ${name}! You have ${count} messages.`
```
The tag is called as `tag(strings, ...values)` where `strings` is an array of the raw string segments with a `.raw` property and `values` are the interpolated expressions.

HTML-escaping example:
```js
const esc = (s) => String(s).replace(/[&<>"']/g, c => ({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
}[c]));

function html(strings, ...values) {
  return strings.reduce(
    (out, s, i) => out + s + (i < values.length ? esc(values[i]) : ''),
    ''
  );
}
const user = '<script>alert(1)</script>';
html`<p>Hi ${user}</p>`; // "<p>Hi &lt;script&gt;alert(1)&lt;/script&gt;</p>"
```
Libraries such as `lit-html` and the `sql` tag in `postgres.js` use this pattern for safe, composable templating.

### JS14 — Easy
**Answer:**
**Destructuring** unpacks values from arrays or properties from objects into distinct bindings.

**Object destructuring**:
```js
const user = { id: 1, name: 'Ada', role: 'admin' };
const { name, role } = user;
const { name: userName } = user;          // rename
const { missing = 'default' } = user;     // default
const { name, ...rest } = user;           // rest → { id:1, role:'admin' }
```

**Array destructuring** (positional):
```js
const [a, b, , d] = [1, 2, 3, 4];  // a=1, b=2, d=4 (hole skipped)
const [head, ...tail] = [1, 2, 3]; // head=1, tail=[2,3]
const [x = 10] = [];               // x=10
```

**In function parameters**:
```js
function greet({ name, greeting = 'hi' } = {}) { /* ... */ }
```

**Rest `...`** in destructuring collects the remaining elements/properties into a new array/object. In function parameter lists (`function f(...args)`), it gathers remaining arguments into an array. The same `...` token is also the **spread** operator in value position (e.g., `[...a, ...b]`, `{...a, ...b}`, `fn(...args)`).

### JS15 — Easy
**Answer:**
- **`for (const k in obj)`** iterates over **enumerable string-keyed properties** of an object, including those inherited via the prototype chain. It yields *keys* (strings — even for arrays, indices are strings).
- **`for (const v of iterable)`** iterates over values produced by an *iterable* (anything with a `Symbol.iterator` method) — arrays, strings, `Map`, `Set`, `NodeList`, generators, etc. It yields *values*.

```js
const arr = ['a','b','c'];
arr.extra = 'x';
for (const k in arr) console.log(k);  // '0','1','2','extra' (+ any inherited enumerable)
for (const v of arr) console.log(v);  // 'a','b','c'
```

**Avoid `for...in` on arrays** because:
1. It iterates indices as strings and may visit them in any order (specified for integer-indexed properties but implementation details still bite).
2. It picks up inherited and non-index enumerable properties (like polyfills added to `Array.prototype`, or your own `.extra`).
3. It's slower than index loops / `for...of`.

Use `for...of`, `arr.forEach`, or a classical `for (let i = 0; i < arr.length; i++)` for arrays. `for...in` is for plain objects when you need keys (and even then, `Object.keys/entries` is usually clearer).

### JS16 — Medium
**Answer:**
**Generics** let types and functions be parameterized by other types.
```ts
function identity<T>(x: T): T { return x; }
const n = identity<number>(42); // T inferred as number if omitted
```

**Generic constraints** (`extends`) restrict what a type parameter can be:
```ts
function getLength<T extends { length: number }>(x: T): number {
  return x.length;
}
getLength('abc');   // ok, string has length
getLength([1,2]);   // ok
// getLength(42);   // error
```

**Conditional types** (`T extends U ? X : Y`) pick between two types based on assignability. Over a naked type parameter they *distribute* over unions:
```ts
type NonNull<T> = T extends null | undefined ? never : T;
type A = NonNull<string | null>; // string
```

**`infer`** introduces a new type variable inside a conditional type's `extends` clause, letting you extract a piece of another type:
```ts
type ReturnType<F> = F extends (...args: any[]) => infer R ? R : never;
type R = ReturnType<() => string>; // string

type ElementOf<T> = T extends (infer U)[] ? U : never;
type E = ElementOf<number[]>; // number

type Awaited2<T> = T extends Promise<infer U> ? Awaited2<U> : T;
```

Combined, these enable the utility types shipped with TypeScript (`ReturnType`, `Parameters`, `InstanceType`, `Awaited`, etc.).

### JS17 — Medium
**Answer:**
JavaScript has two main module systems:

**CommonJS (CJS)** — Node's original system:
```js
const fs = require('fs');
module.exports = { foo };
```
- Loaded synchronously and dynamically (`require` is a function call).
- Each file has `module`, `exports`, `require`, `__dirname`, `__filename` injected.
- `module.exports` is a mutable object; imports are references to it at require time (but primitive re-exports are copied).

**ES Modules (ESM)** — the standard:
```js
import fs from 'node:fs';
export function foo() {}
export default value;
```
- Static syntax — `import`/`export` must be at the top level (top-level `await` is allowed).
- Asynchronous loading/linking; imports are *live bindings* (views into the exporter's scope — if the exporter changes `export let x`, importers see the new value).
- `this` at top level is `undefined`, no `__dirname`/`__filename` (use `import.meta.url` + `fileURLToPath`).

**Node's resolution** depends on whether a file is treated as CJS or ESM:
- `.cjs` → CJS; `.mjs` → ESM.
- `.js` → depends on the nearest `package.json`'s `"type"` field: `"type": "module"` makes `.js` be ESM, otherwise it's CJS (default).
- ESM can `import` CJS (it's wrapped — default export is `module.exports`, named exports are a best-effort static analysis).
- CJS can load ESM only asynchronously via `await import('...')` (or, recent Node versions, synchronous `require()` of ESM if fully synchronous).

`"type": "module"` in `package.json` flips the default interpretation of `.js` files in that package to ESM.

### JS18 — Hard
**Answer:**
TypeScript uses a **structural type system**: two types are compatible if their *shapes* are compatible, regardless of nominal identity. If `A` has all members that `B` requires (with compatible types), `A` is assignable to `B`.
```ts
interface Point { x: number; y: number }
const p = { x: 1, y: 2, z: 3 };
const q: Point = p; // OK — extra z is allowed for variables
```

**Excess property checks**: when you assign an **object literal** *directly* to a typed slot (variable declaration with annotation, function argument, return position), TS additionally flags properties that aren't in the target type:
```ts
const q: Point = { x: 1, y: 2, z: 3 }; // Error: 'z' does not exist on 'Point'
```
Assigning through an intermediate variable bypasses the check (normal structural rules apply). This is a heuristic to catch typos, not a soundness rule.

**`extends` vs `satisfies`**:
- `extends` (in conditional types, `interface ... extends`, generic constraints) checks assignability and either narrows or constrains.
- **`satisfies`** (TS 4.9+) verifies that an expression matches a type **without widening or changing the inferred type** of the expression. It's ideal when you want both *validation* and *precise inference*:
  ```ts
  const palette = {
    red: [255, 0, 0],
    green: '#00ff00',
  } satisfies Record<string, [number, number, number] | string>;
  // palette.red is inferred as [number, number, number] (tuple), not string|tuple
  ```

**Variance annotations (TS 4.7+)**: `in` / `out` / `in out` let you explicitly declare a generic parameter as contravariant / covariant / invariant, primarily as an optimization hint and to catch variance mistakes:
```ts
interface Getter<out T> { get(): T }           // covariant
interface Setter<in T>  { set(x: T): void }    // contravariant
interface Box<in out T> { value: T }           // invariant
```
TypeScript infers variance automatically; annotations are checked against inferred variance and help readability plus type-checker performance.

### JS19 — Hard
**Answer:**
**`Proxy`** wraps a target object with a handler containing *traps* that intercept fundamental operations:
```js
const p = new Proxy(target, {
  get(t, prop, recv)        { /* property read */ },
  set(t, prop, val, recv)   { /* property write; return true */ },
  has(t, prop)              { /* `prop in p` */ },
  deleteProperty(t, prop)   { /* `delete p.prop` */ },
  apply(t, thisArg, args)   { /* function call: p(...) */ },
  construct(t, args, newT)  { /* `new p(...)` */ },
  ownKeys, getOwnPropertyDescriptor, defineProperty,
  getPrototypeOf, setPrototypeOf, isExtensible, preventExtensions,
});
```

**`Reflect`** is a built-in object that exposes the default implementations of those same operations as functions (`Reflect.get`, `Reflect.set`, `Reflect.has`, `Reflect.apply`, `Reflect.construct`, etc.). Inside a trap you typically forward to `Reflect` to preserve correct semantics (including the `receiver` for getters/setters).

**Example — validating setter + logging**:
```js
function observable(obj, onChange) {
  return new Proxy(obj, {
    get(t, p, r) {
      const v = Reflect.get(t, p, r);
      return typeof v === 'object' && v !== null ? observable(v, onChange) : v;
    },
    set(t, p, v, r) {
      if (p === 'age' && typeof v !== 'number') {
        throw new TypeError('age must be a number');
      }
      const ok = Reflect.set(t, p, v, r);
      if (ok) onChange(p, v);
      return ok;
    },
  });
}

const user = observable({ name: 'Ada', age: 30 }, (k, v) =>
  console.log(`${String(k)} = ${v}`));
user.age = 31; // logs "age = 31"
```
This is exactly the pattern used by reactive frameworks (Vue 3 `reactive`, MobX, Immer).

### JS20 — Hard
**Answer:**
**`SharedArrayBuffer`** is a raw byte buffer whose underlying memory can be *shared* between the main thread and Web Workers (or Worker threads in Node). You post it with `worker.postMessage(sab)`; both sides wrap it in a typed array (`Int32Array`, `BigInt64Array`, etc.) to read/write the same physical memory.

Because it allows true concurrent access, the browser requires cross-origin isolation (`COOP: same-origin` + `COEP: require-corp` headers) to enable it, due to Spectre mitigations.

**`Atomics`** provides atomic, race-free operations on integer-typed views of a `SharedArrayBuffer`:
- `Atomics.load/store` — atomic read/write.
- `Atomics.add/sub/and/or/xor` — atomic RMW, returns previous value.
- `Atomics.compareExchange(ta, i, expected, replacement)` — CAS.
- `Atomics.exchange` — atomic swap.

**Ordering**: Atomics operations are **sequentially consistent** — all agents observe a single total order of atomic ops, and non-atomic accesses cannot be reordered across them. Non-atomic accesses to shared memory have no ordering guarantees and can produce "racy" values; you should synchronize via atomics.

**`Atomics.wait` / `Atomics.notify`** implement a futex-like blocking primitive:
- `Atomics.wait(i32, index, expectedValue, timeoutMs?)` — if `i32[index] === expectedValue`, the calling agent blocks until notified, times out, or the value changes. Returns `'ok' | 'timed-out' | 'not-equal'`. Only allowed on worker threads (not the main browser thread; `Atomics.waitAsync` is the non-blocking variant).
- `Atomics.notify(i32, index, count)` — wakes up to `count` waiters parked on that index.

Typical pattern — mutex/condition variable:
```js
// writer
Atomics.store(i32, 0, 1);
Atomics.notify(i32, 0, 1);

// reader (worker)
if (Atomics.load(i32, 0) === 0) {
  Atomics.wait(i32, 0, 0);
}
// proceed
```
Use cases: high-performance parallel compute, WASM threading (pthreads compile down to this), ring buffers between worker and main thread, lock-free data structures.

---

## Section 2: Bash (B1–B20)

### B1 — Easy
**Answer:**
Inside a script/function that receives positional parameters:

- **`$@`** (unquoted): expands to all positional parameters subject to word splitting and glob expansion — equivalent to `$1 $2 $3 ...`.
- **`$*`** (unquoted): the same.
- **`"$@"`**: expands to *separate, individually quoted* words: `"$1" "$2" "$3" ...`. Each parameter stays intact even if it contains spaces or glob characters. **This is almost always what you want** when forwarding arguments.
- **`"$*"`**: expands to a **single** string with all parameters joined by the first character of `IFS` (default: space): `"$1c$2c$3"`. Use only when you want a single concatenated string.

```bash
set -- 'one two' 'three'
printf '[%s]\n' "$@"   # [one two] [three]
printf '[%s]\n' "$*"   # [one two three]
```

Rule: forward with `cmd "$@"`, never `cmd $@` or `cmd "$*"`.

### B2 — Easy
**Answer:**
`set -euo pipefail` is the canonical "strict mode" prelude:

- **`-e`** (`errexit`): exit the script immediately if any simple command returns a non-zero status (with some exceptions: commands in `if`/`while`/`until` conditions, the left side of `&&`/`||`, commands prefixed with `!`, and the last command in a pipeline without `pipefail`).
- **`-u`** (`nounset`): treat references to unset variables and parameters as an error and exit (except `$@` and `$*` when empty). Forces you to declare variables or provide defaults (`${var:-}`).
- **`-o pipefail`**: change the exit status of a pipeline so that it is the exit status of the rightmost command that failed (or zero if all succeeded). Without it, `false | true` has exit status 0, hiding the failure of `false`.

Often combined with `IFS=$'\n\t'` and `set -x` (for debugging). Know the gotchas: `-e` doesn't trigger inside command substitution used in assignments (`x=$(might_fail)` — check `$?` explicitly), and doesn't propagate into subshells unless you also set `-E` for `ERR` traps.

### B3 — Medium
**Answer:**
**`$(command)` vs \`command\`** — both perform *command substitution* (run `command`, capture its stdout, strip trailing newlines, substitute into the surrounding context):
- `$(...)` is POSIX, nests cleanly (`$(a $(b) c)`), quotes naturally, and is the preferred form.
- Backticks are legacy: nesting requires escaping (`` `a \`b\` c` ``), and backslash rules inside are surprising. Avoid in new code.

**`$(( expression ))` vs `expr`** — integer arithmetic:
- `$((...))` is a bash/POSIX *arithmetic expansion*. It's a shell built-in, so no fork, supports C-like operators (`+ - * / % ** & | ^ << >> && || ?: =`), ignores `$` on variable names, and the result is substituted in place:
  ```bash
  i=5
  echo $(( i * 2 + 1 ))   # 11
  ```
- `expr` is an external program inherited from System V Unix. It requires *space-separated* tokens and escaping of shell metacharacters (`expr 5 \* 2`). Forks a process per call, limited to integers, and is slower. Only use for POSIX sh portability when `$((...))` isn't available (which is essentially never in bash).

Also relevant: `((...))` is a *command* form for arithmetic (exit status, use in `if`/`while`), and `let` does the same.

### B4 — Medium
**Answer:**
**Process substitution** `<(cmd)` (and `>(cmd)`) makes a command's stdout (or stdin) appear as a filename (`/dev/fd/63` on Linux) that other commands can open. This is useful when a program expects a file path but you have the data as a command output, and you don't want to write a temp file.

Under the hood bash sets up a pipe and substitutes the `/dev/fd/N` path of the reading end. It's a bash/ksh/zsh feature — not POSIX.

Classic use with `diff` to compare the output of two commands without temp files:
```bash
diff <(sort fileA | uniq) <(sort fileB | uniq)
```
Other examples:
```bash
# Compare directory listings
diff <(ls dir1) <(ls dir2)

# Feed multiple command outputs to a program
paste <(cut -f1 a.tsv) <(cut -f2 b.tsv)

# Tee stdout to a filter while still writing to a file
some_cmd > >(gzip > out.log.gz)
```
Note that process substitution has no cleanly observable exit status of the substituted command (check `wait`, `PIPESTATUS`, or use a fifo if you need it).

### B5 — Easy (actually Medium per source)
**Answer:**
Use a `for` loop over a glob directly, or `find ... -print0 | xargs -0`, or `while read -d ''`. Never iterate the output of `ls`.

```bash
# Safe: glob directly (bash handles any filename)
shopt -s nullglob    # empty glob → no iterations, not a literal '*'
for f in ./*.log; do
  process "$f"       # always quote the expansion
done
```

For recursive traversal with NUL separation:
```bash
find . -type f -name '*.log' -print0 |
  while IFS= read -r -d '' f; do
    process "$f"
  done
```

Or with `xargs`:
```bash
find . -type f -name '*.log' -print0 | xargs -0 -n1 process
```

**Why `for f in $(ls)` is broken**:
1. `ls` prints filenames separated by newlines (or spaces); the unquoted `$(ls)` is split by bash on `$IFS` (spaces, tabs, newlines by default). A filename `hello world.txt` becomes two words `hello` and `world.txt`.
2. The shell then *glob-expands* each word, so a filename containing `*` turns into whatever matches in the current directory.
3. Newlines in filenames (legal on Unix!) break the output even without word splitting.
4. `ls` may colorize or localize output, further corrupting things.

ShellCheck rule SC2045 flags this for exactly this reason. Always iterate globs or `find -print0`.

### B6 — Medium
**Answer:**
- **Here document** `<<EOF` redirects a block of literal text as stdin to a command. The block ends at a line containing exactly the delimiter (here `EOF`). Parameter expansion, command substitution, and arithmetic expansion happen inside unless you **quote the delimiter** (`<<'EOF'`), which turns off all expansions — useful for embedding scripts verbatim.
  ```bash
  cat <<EOF
  Hello, $USER — date is $(date +%F)
  EOF
  ```

- **Here string** `<<<` passes a single word/string as stdin, with a trailing newline appended:
  ```bash
  grep foo <<< "$text"
  bc <<< "2+2"
  ```

- **`<<-EOF`** is a heredoc variant that **strips leading tab characters** (only tabs, not spaces) from each line, including the closing delimiter. This lets you indent the heredoc with the surrounding code without breaking the terminator match:
  ```bash
  if true; then
  	cat <<-EOF
  		line 1
  		line 2
  	EOF
  fi
  ```
  Note: tabs only — if your editor expands tabs to spaces, the stripping won't happen. Some teams use `cat <<-EOF` with `sed 's/^ *//'` or `printf` to avoid the tab requirement.

### B7 — Hard
**Answer:**
Redirections are processed **left to right**, and `2>&1` means "make fd 2 a duplicate of whatever fd 1 currently points to" — a **snapshot**, not a live link.

- **`cmd > file 2>&1`**
  1. `> file` — fd 1 is redirected to `file`.
  2. `2>&1` — fd 2 is duplicated from fd 1, which now points to `file`.
  Result: both stdout and stderr go to `file`. This is the idiomatic "capture everything" form.

- **`cmd 2>&1 > file`**
  1. `2>&1` — fd 2 is duplicated from fd 1, which (at this point) still points to the terminal/parent stdout.
  2. `> file` — fd 1 is *then* redirected to `file`. fd 2 is unaffected; it still points to the original terminal.
  Result: stdout goes to `file`, stderr goes to the terminal. Almost never what you want.

- **`cmd &> file`** (bash extension; also `&>>` for append) is shorthand for `> file 2>&1` — both fds to `file`. POSIX-portable equivalent is `> file 2>&1`.

The difference in the first two comes from the fact that `2>&1` copies the *current* target of fd 1 at the moment of evaluation, not a reference to "whatever fd 1 will be later".

### B8 — Hard
**Answer:**
```bash
#!/usr/bin/env bash
set -euo pipefail

LOCK_DIR="/tmp/myscript.lock.d"

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

acquire_lock() {
  # mkdir is atomic on POSIX filesystems: it either creates the dir
  # or fails with EEXIST — no race between "check" and "create".
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another instance is running (lock: $LOCK_DIR)" >&2
    exit 1
  fi
  # Ensure we always clean up, even on normal exit, errors, or signals.
  trap cleanup EXIT
  trap 'trap - EXIT; cleanup; exit 130' INT
  trap 'trap - EXIT; cleanup; exit 143' TERM
  # Optional: record the PID for debugging and stale-lock detection.
  echo "$$" > "$LOCK_DIR/pid"
}

acquire_lock
# ... critical section ...
```

**Why `mkdir` instead of a regular file?** Creating a file then writing to it is a two-step "test and set": `[ -f lock ] || touch lock` has a TOCTOU race — two processes can both see "no lock" and both `touch`. `mkdir` is a **single atomic syscall** that either succeeds (you own the lock) or fails with `EEXIST` (someone else has it). No race. On NFS, older lockfile tricks (`ln`, `O_EXCL` open) were flaky; `mkdir` is reliable on any POSIX-compliant filesystem.

For more robust locking on Linux, `flock(1)` is even better (auto-release on process death, no stale locks):
```bash
exec 9>/var/lock/myscript.lock
flock -n 9 || { echo "already running" >&2; exit 1; }
```

Stale-lock handling for `mkdir` locks usually reads the stored PID and checks if that process is still alive (`kill -0 "$pid"`); if not, remove and retry (with another race window, so add a randomized sleep).

### B9 — Easy
**Answer:**
- **Single quotes `'...'`** — absolutely literal. No expansion of anything, not even `\`. You cannot include a `'` inside. Use for fixed strings.
- **Double quotes `"..."`** — preserve spaces and most metacharacters but **do** perform: parameter expansion (`$var`, `${var}`), command substitution (`$(...)`), arithmetic expansion (`$((...))`), and backslash escapes for `$`, `` ` ``, `"`, `\`, and newline. Globs are *not* expanded. Prefer this when interpolating variables.
- **No quotes** — the value is subject to *word splitting* on `$IFS` and *pathname (glob) expansion*. Useful for intentional splitting; a bug source otherwise.

```bash
name='Ada Lovelace'
files='*.txt'

echo '$name $files'  # $name $files         (literal)
echo "$name $files"  # Ada Lovelace *.txt    (expanded, no split/glob)
echo $name $files    # Ada Lovelace a.txt b.txt ...  (split + glob)
```
Rule of thumb: quote everything unless you have a concrete reason not to.

### B10 — Easy
**Answer:**
Use the `test` operators (either `[ ... ]` or `[[ ... ]]`):

```bash
[[ -e path ]]    # exists (any type)
[[ -f path ]]    # regular file
[[ -d path ]]    # directory
[[ -L path ]]    # symlink
[[ -r path ]]    # readable
[[ -w path ]]    # writable
[[ -x path ]]    # executable
[[ -s path ]]    # exists and non-empty
```
```bash
if [[ -f "$file" && -r "$file" ]]; then
  echo "readable regular file"
fi
```

**`[ ]` (single bracket / `test`)**:
- POSIX built-in (actually a command — `/usr/bin/[` exists).
- Arguments are subject to word splitting and globbing, so you **must quote variables** (`[ -f "$file" ]`) or you'll get errors when they're empty or contain spaces.
- Uses `-a`, `-o`, `=` for and/or/equality. `<` and `>` inside need escaping.

**`[[ ]]` (double bracket, bash/ksh/zsh extension)**:
- A shell *keyword*, not a command — parsed specially.
- No word splitting or glob expansion on variables, so `[[ -f $file ]]` is safe even unquoted.
- Supports `&&`, `||`, `<`, `>`, parentheses for grouping.
- Adds `==` with pattern matching (`[[ $x == *.log ]]`) and `=~` with regex (`[[ $x =~ ^[0-9]+$ ]]`).
- Not POSIX — use `[ ]` only if you need `sh` portability.

In bash scripts, prefer `[[ ]]`.

### B11 — Easy
**Answer:**
- **`$?`** — exit status of the *most recently completed foreground command/pipeline*. Use after a call to branch on success/failure or to save the code:
  ```bash
  some_cmd; rc=$?
  if [[ $rc -ne 0 ]]; then ...; fi
  ```
- **`$$`** — PID of the *current shell* (fixed across subshells too — it's the parent shell's PID). Used for per-run temp files: `tmp="/tmp/foo.$$"`.
- **`$!`** — PID of the *most recently backgrounded* command (`cmd &`). Use to `wait` on or `kill` a specific background job:
  ```bash
  long_task &
  pid=$!
  trap 'kill $pid 2>/dev/null' EXIT
  wait $pid
  ```
- **`$#`** — number of positional parameters currently set. Use to validate CLI usage:
  ```bash
  if (( $# < 2 )); then
    echo "usage: $0 <src> <dst>" >&2
    exit 2
  fi
  ```

Bonus: `$0` is the script name, `$-` is current shell option flags, `$_` is the last argument of the previous command.

### B12 — Easy
**Answer:**
Two equivalent syntaxes for defining a function:

```bash
# POSIX form (portable)
greet() {
  echo "hello, $1"
}

# bash/ksh "function" keyword form (not POSIX)
function greet {
  echo "hello, $1"
}
```
The combined `function greet() { ... }` form works in bash but isn't portable. Prefer the POSIX `name()` form in scripts that may run under `sh`, and use `local` for variables inside functions to avoid polluting the caller's scope.

**Difference**: functionally identical in bash. The `function` keyword is a ksh-ism retained for compatibility; with it you can omit `()`. Some very old shells parse them slightly differently, but you won't encounter them in practice.

**Returning values**: bash functions can only *return an exit status* (0–255) via `return N`. To "return" data, you have two options:
1. **Print to stdout and capture with command substitution**:
   ```bash
   add() { echo $(( $1 + $2 )); }
   sum=$(add 2 3)   # 5
   ```
2. **Write to a caller-supplied variable name** (`declare -n` nameref, bash 4.3+):
   ```bash
   add() { local -n out=$3; out=$(( $1 + $2 )); }
   add 2 3 result
   echo "$result"   # 5
   ```

Call: `greet "world"` (no parentheses, positional args like any command). Inside: `$1`, `$2`, ..., `$@`, `$#` refer to the function's arguments. `return` (without args) returns the exit status of the last command.

### B13 — Easy
**Answer:**
**`PATH`** is a colon-separated list of directories the shell searches, in order, for external commands:
```
/usr/local/bin:/usr/bin:/bin:/usr/sbin
```
When you type `ls`, bash walks `PATH` left to right, picking the first executable match (and caching the result in its hash table). The current directory is **not** on `PATH` by default, and you shouldn't add it for security reasons.

**How bash resolves `name`**:
1. **Aliases** (if expanded and interactive).
2. **Keywords** (`if`, `while`, ...).
3. **Functions** defined in the current shell.
4. **Built-ins** (like `cd`, `echo`, `export`, `read`, `pwd`, `test`, `printf`). These are implemented inside the shell — no fork/exec.
5. **Hashed commands** (previously resolved external commands).
6. **PATH lookup** — fork/exec an external program.

**Builtin vs external** matters because:
- Builtins are faster (no process creation) and can affect the current shell (`cd`, `export`, `read`). External commands run in a child process and can't change the parent's environment.
- Some names exist both as a builtin and an external (`echo`, `test`, `printf`, `[`), with subtly different flags.

**Check what bash will run**:
```bash
type -a ls        # shows all matches in resolution order
type cd           # → "cd is a shell builtin"
command -v ls     # → "/usr/bin/ls" (or alias/function name)
which ls          # external program; less reliable than `type`
hash              # show the hashed-command table
```
Use `type -a` — it's the bash-aware answer.

### B14 — Medium
**Answer:**
`trap` installs a handler for a signal or a pseudo-signal. Syntax:
```bash
trap 'handler_code' SIG1 SIG2 ...
trap - SIG              # reset to default
trap '' SIG             # ignore
trap -p                 # list installed traps
```

Common pseudo-signals:
- **`EXIT`** — runs when the shell (or function, if `local` set) terminates, from any path: normal exit, `exit` call, or uncaught signal. Ideal for cleanup (temp files, locks).
- **`ERR`** — runs whenever a command returns non-zero under `set -e`/`-E`. Not inherited by functions/subshells unless `set -E` (`errtrace`).
- **`INT`** — SIGINT (Ctrl-C).
- **`TERM`** — SIGTERM (default `kill`).
- **`HUP`** — SIGHUP (terminal closed, daemon reload).
- **`DEBUG`**, **`RETURN`** — for tracing.

Typical cleanup pattern:
```bash
tmp=$(mktemp -d)
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT
trap 'echo interrupted >&2; exit 130' INT TERM
```
Setting `EXIT` alone is often enough because a signal that kills the script still fires `EXIT` — but explicit `INT`/`TERM` handlers let you exit with the conventional `128 + signum` status and perhaps log extra info.

**Multiple-signal ordering**: bash processes signals *synchronously* between commands. If multiple signals arrive while a command is running, they're queued and delivered one-per-iteration in an implementation-defined order; most commonly SIGINT is handled first. SIGKILL (9) and SIGSTOP (19) **cannot be trapped** — the kernel kills/stops the process immediately. For reliable ordering, rely only on the single-signal case and write handlers to be idempotent.

### B15 — Medium
**Answer:**
**Command substitution** (`$(...)`) runs a command and textually substitutes its output, subject to word splitting and globbing. It's fine for small, bounded output but fails on long arg lists (`E2BIG`) and on filenames with spaces/newlines.

**`xargs`** reads items from stdin and constructs command lines from them, respecting the system's `ARG_MAX`:
```bash
echo a b c | xargs echo   # echo a b c
```
By default `xargs` splits on whitespace and interprets quotes/backslashes — dangerous for filenames.

**Safe filename handling**: use NUL as the separator. `find -print0` emits paths separated by NUL (which can't appear in filenames); `xargs -0` reads them:
```bash
find . -type f -name '*.log' -print0 | xargs -0 rm -v --
```
Other useful flags:
- `-n N` — at most `N` args per command line (controls batching).
- `-I {}` — replace-string form, one invocation per item: `xargs -0 -I{} mv {} archive/`.
- `-r` (`--no-run-if-empty`) — don't run the command at all if stdin is empty (GNU xargs default varies).
- `--` — end-of-options for the target command.

**`xargs -P N`** runs up to `N` commands in **parallel**. Combined with `find -print0` and a per-file processing step this gives trivial fan-out:
```bash
find . -type f -name '*.log' -print0 |
  xargs -0 -n1 -P "$(nproc)" gzip -9
```
Caveats: output from parallel jobs can interleave (use `--line-buffered` or per-job log files). Error propagation is limited — `xargs` exits non-zero if any child failed, but doesn't stop siblings (unless you also pass `-P1` or write your own orchestration).

### B16 — Medium
**Answer:**
**Indexed arrays** (default, integer keys):
```bash
arr=(foo bar baz)           # declare + init
arr[3]="qux"                # assign at index
arr+=(more items)           # append
echo "${arr[0]}"            # 'foo'
echo "${arr[@]}"            # all elements as separate words (prefer "${arr[@]}")
echo "${#arr[@]}"           # length (4 then 6)
for v in "${arr[@]}"; do    # iterate values
  echo "$v"
done
for i in "${!arr[@]}"; do   # iterate indices
  echo "$i -> ${arr[$i]}"
done
unset 'arr[2]'              # delete index (leaves a hole)
```

**Associative arrays** (bash 4+, must be declared):
```bash
declare -A map              # REQUIRED
map[alice]=30
map[bob]=25
map+=( [carol]=40 [dave]=35 )

echo "${map[alice]}"        # 30
echo "${#map[@]}"           # number of entries
for k in "${!map[@]}"; do   # iterate keys (unordered!)
  echo "$k = ${map[$k]}"
done
echo "${map[@]}"            # values, unordered
[[ -v map[alice] ]] && echo "alice exists"
unset 'map[bob]'
```

**Differences**:
- Declaration: indexed arrays can be implicit (`arr=(...)`); associative *must* be `declare -A` (or `typeset -A`).
- Key type: integer vs string.
- Iteration order: indexed is by index order; associative is *unordered* (hash-based).
- Associative arrays are bash-only (not ksh-compatible in the same syntax) and were added in 4.0 (2009).
- Both: quote the expansion (`"${arr[@]}"`), use `${!arr[@]}` for keys/indices, `${#arr[@]}` for length.

### B17 — Hard
**Answer:**
**Subshell `( ... )`** — commands run in a forked child shell. Variable assignments, `cd`, `shopt`, `set`, `trap`, etc. inside the subshell do **not** affect the parent. The exit status of the group is the exit status of the last command.
```bash
(
  cd /tmp
  x=42
  exit 3
)
echo "$x"   # unset
echo $?     # 3
```

**Group command `{ ...; }`** — commands run in the *current* shell; it's just a syntactic grouping for redirection or conditional execution. Assignments and `cd` persist.
```bash
{
  cd /tmp
  x=42
} > /dev/null
echo "$x"   # 42
```
Note the syntactic quirks of `{ }`: the braces must be separated by whitespace from their contents, and the last command needs a terminator (`;` or newline) before `}`.

**Why piping into `while` loses changes**:
```bash
count=0
seq 1 5 | while read -r n; do
  count=$((count + 1))
done
echo "$count"   # 0, not 5
```
Each component of a pipeline runs in its own *subshell* (in bash by default). The `while` loop on the right runs in a child shell, so `count` is incremented only in that child and discarded when it exits.

**Fixes**:
1. **Process substitution + input redirection** keeps `while` in the current shell:
   ```bash
   while read -r n; do ((count++)); done < <(seq 1 5)
   ```
2. **Here string** for small inputs: `while read ...; done <<< "$data"`.
3. **`shopt -s lastpipe`** (bash 4.2+, **non-interactive** shells only): causes the last command of a pipeline to run in the current shell:
   ```bash
   shopt -s lastpipe
   seq 1 5 | while read -r n; do ((count++)); done
   echo "$count"   # 5
   ```

### B18 — Hard
**Answer:**
**Signals**:
- **SIGINT (2)** — "interrupt": sent by terminal when you hit Ctrl-C. Default action: terminate. Programs typically catch it to clean up gracefully. Conventional exit code `128 + 2 = 130`.
- **SIGTERM (15)** — "terminate": polite request to exit, the default for `kill PID`. Catchable; the target decides how to handle it (graceful shutdown, drain, flush). Conventional exit `143`.
- **SIGHUP (1)** — "hang up": historically sent when the controlling terminal disconnected. Modern daemons reuse it as "reload config". Exit `129` if untrapped.
- **SIGKILL (9)** — *uncatchable, unblockable, unignorable*. The kernel kills the process immediately with no chance to clean up. Use as last resort; prefer TERM first, then KILL after a grace period. Also SIGSTOP (17/19) is similarly untrappable but pauses instead of killing.

Order of escalation most init systems use: `TERM → wait grace period → KILL`.

**Graceful shutdown with background processes**:
```bash
#!/usr/bin/env bash
set -euo pipefail

pids=()

start_worker() {
  some_worker "$1" &
  pids+=($!)
}

shutdown() {
  echo "shutting down..." >&2
  # Forward signal to children; kill -TERM is default.
  for pid in "${pids[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done
  # Give them a few seconds to exit cleanly.
  local deadline=$((SECONDS + 10))
  for pid in "${pids[@]}"; do
    while kill -0 "$pid" 2>/dev/null && (( SECONDS < deadline )); do
      sleep 0.1
    done
    kill -KILL "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  exit 0
}

trap shutdown INT TERM HUP

start_worker job1
start_worker job2

# Wait for any to exit; re-enter wait if interrupted by signals.
while wait -n 2>/dev/null; do :; done
```

Key points: trap the signals, forward them to children (bash does *not* propagate signals to background jobs automatically), use `wait -n` to block until any child exits while still allowing traps to fire, and fall back to SIGKILL after a deadline.

### B19 — Hard
**Answer:**
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT="${1:?usage: $0 <logfile>}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

JOBS="$(nproc)"
LINES_PER_CHUNK=100000

# 1. Split the log into N numbered chunks.
split -l "$LINES_PER_CHUNK" -d --additional-suffix=.chunk "$INPUT" "$WORK/part-"

# 2. Per-chunk processing function. Must be exported so xargs sh -c can see it.
process_chunk() {
  local f="$1"
  local out="${f}.out"
  # Example: count 5xx responses per URL path.
  awk '$9 ~ /^5[0-9][0-9]$/ { print $7 }' "$f" | sort | uniq -c > "$out" || return $?
}
export -f process_chunk

# 3. Parallel fan-out with xargs -P. Each job writes its own output file,
#    so stdout never interleaves. -print0/-0 handles weird filenames.
find "$WORK" -maxdepth 1 -name 'part-*.chunk' -print0 |
  xargs -0 -n1 -P "$JOBS" bash -c 'process_chunk "$0"' ||
  { echo "one or more workers failed" >&2; exit 1; }

# 4. Merge partial results. For this example, re-aggregate counts per URL.
cat "$WORK"/part-*.chunk.out |
  awk '{ counts[$2] += $1 } END { for (u in counts) printf "%8d %s\n", counts[u], u }' |
  sort -rn
```

**Performance trade-offs**:
- **CPU parallelism vs disk I/O**: splitting forces you to read the file twice (once to split, once per chunk). For I/O-bound workloads on a single spinning disk, more workers can *slow things down* due to seeks. On NVMe or for CPU-heavy awk/regex work, near-linear speedup up to `nproc`.
- **Chunk size**: too small → startup overhead dominates; too large → stragglers. Rule of thumb: aim for each chunk to take 1–10 s.
- **Memory**: each parallel job runs its own process tree; watch RSS × `-P`.
- **Merge cost**: the merge is serial. If the per-chunk output is tiny (aggregations, counts) this is cheap; if it's "just re-split" streams, the merge becomes the bottleneck.

**Error propagation from parallel jobs**:
- `xargs` returns non-zero if any invocation failed (exit codes 123 for 1–125, 124 for a 255, 125 for `xargs` errors), but it does *not* cancel siblings by default.
- Use `xargs --halt now,fail=1` (GNU parallel has richer options) or wrap the loop and check `$?` explicitly.
- Alternative: GNU `parallel` handles `--halt`, progress, per-job logs, and result joining much more cleanly:
  ```bash
  find "$WORK" -name 'part-*.chunk' |
    parallel --halt now,fail=1 -j "$JOBS" process_chunk
  ```
- Always write worker stdout/stderr to per-job files to avoid interleaving, and aggregate after.
- Return non-zero from worker functions on partial failure so `xargs`/`parallel` can see it.

### B20 — Hard
**Answer:**
**`exec` without a command** modifies the *current* shell's file descriptors. **`exec` with a command** replaces the current shell process with that command — no new process, no `$?` after it, no lines below execute:
```bash
exec my_daemon     # shell is replaced; nothing below runs
```
This is the standard way to chain into another program while preserving PID (init scripts, container entrypoints, shebang wrappers).

**FD manipulation with `exec`**:
```bash
exec 3> out.log           # open fd 3 for writing to out.log
echo "hello" >&3          # write to fd 3
exec 3>&-                 # close fd 3

exec 4< in.txt            # fd 4 for reading
while read -r line <&4; do echo "$line"; done
exec 4<&-

exec 5<> /dev/tcp/host/80 # open read/write network socket on fd 5 (bash feature)

exec > >(tee -a log.txt) 2>&1   # redirect ALL further stdout+stderr of the script
```
`3>&-` and `4<&-` close the descriptor. This pattern is useful for scripts that need to log to a file for the remainder of execution, or maintain a long-lived fd to a pipe/socket.

**Bash coprocess** (`coproc`) runs a command asynchronously with its stdin and stdout connected to the parent shell via a pair of pipes:
```bash
coproc BC { bc -l; }         # name "BC", default fds in BC[0] (read) and BC[1] (write)
echo "scale=4; 22/7" >&${BC[1]}
read -r answer <&${BC[0]}
echo "pi ≈ $answer"
exec {BC[1]}>&-              # close write side to signal EOF
wait "$BC_PID"
```
The coprocess's PID is in `${COPROC_PID}` (or `${NAME_PID}` when named), and its fds in `${COPROC[0]}`/`${COPROC[1]}`.

**When to use**: long-lived interactive helpers (a persistent `bc`, `gdb`, `python -i`, a DB client) that you want to drive from a script without re-launching per request. For one-shot "transform data" tasks a regular pipeline is simpler. In practice, coprocesses are niche — most scripts prefer named pipes (`mkfifo`) or just a pipeline, and complex cases escape to Python/Expect.

---

## Section 3: PowerShell (PS1–PS20)

### PS1 — Easy
**Answer:**
- **`Write-Output`** (alias `echo`, or just emitting an expression) puts an object onto the **success pipeline**. It can flow into the next cmdlet, be captured into a variable, redirected, etc. It's how functions return values.
- **`Write-Host`** writes directly to the **host/console** (historically bypassing the pipeline entirely). It returns nothing down the pipeline. In PowerShell 5.0+ it writes to the *Information* stream (stream 6), so it can be redirected with `6>`, but it *still* does not go to the success pipeline.

**Why it matters in pipelines**: because `Write-Host` output can't be piped into other cmdlets or captured, a function that does `Write-Host "processing $x"; return $x * 2` looks right interactively but breaks when consumers try to capture the result:
```powershell
function Bad { Write-Host "hi"; 42 }
$result = Bad    # $result = 42, "hi" bypasses the capture to the console
```
Use `Write-Output` (or just bare expression) to emit data, and reserve `Write-Host` (or better, `Write-Information`, `Write-Verbose`, `Write-Warning`) for messages meant purely for the human. Don Jones' rule: "`Write-Host` is almost always wrong."

### PS2 — Easy
**Answer:**
A PowerShell **pipeline** streams objects (not text) from one cmdlet's output to the next cmdlet's input. Downstream cmdlets can receive input by value (whole object binds to a parameter with `ValueFromPipeline`) or by property name (`ValueFromPipelineByPropertyName`).

- **`ForEach-Object` (alias `foreach`, `%`)** is a **cmdlet** that processes each incoming object *as it streams*. Use when the source is a pipeline, especially for large/infinite sources — memory stays flat:
  ```powershell
  Get-Process | ForEach-Object { $_.Name.ToUpper() }
  ```
  Supports `-Begin`, `-Process`, `-End` script blocks, and since PS 7+ `-Parallel`.

- **`foreach` statement** is a **language keyword** that iterates over a collection already in memory. It does not stream — the right-hand side must be fully evaluated first:
  ```powershell
  foreach ($p in Get-Process) {
      $p.Name.ToUpper()
  }
  ```
  Faster per-iteration (no cmdlet overhead) but needs the whole collection materialized.

**When to use each**:
- `foreach` statement: fixed in-memory collection, performance matters, inside a function where you already have `$items` as an array.
- `ForEach-Object`: the data is coming from a pipeline, you want streaming/low memory, you want `-Parallel`, or you're writing a one-liner.

Note that inside a `ForEach-Object` block, `$_` (or `$PSItem`) is the current object; inside a `foreach` statement, you name the loop variable explicitly.

### PS3 — Medium
**Answer:**
- **`[hashtable]`** — an ordered-ish key/value dictionary (`@{ key = value }`). Unordered by default (use `[ordered]@{...}` for insertion order). Keys/values are untyped. Used for lookup tables, splatting parameters, building JSON inputs. Supports `.ContainsKey()`, `.Keys`, `.Values`, `$ht[$key]` indexing.
  ```powershell
  $ht = @{ Name = 'Ada'; Age = 30 }
  $ht['Name']        # 'Ada'
  $ht.Keys
  ```

- **`[PSCustomObject]`** — a first-class object with typed members; shows nicely in `Format-Table`, supports dot-property access, round-trips through `Export-Csv`, `ConvertTo-Json`, `Select-Object`, and the pipeline generally. Since PS 3.0 you create it from an ordered hashtable with a cast:
  ```powershell
  $obj = [PSCustomObject]@{ Name = 'Ada'; Age = 30 }
  $obj.Name          # 'Ada'
  $obj | Format-Table
  ```
  Properties remain in the order you wrote them (the `[PSCustomObject]` cast implicitly treats the literal as ordered).

**When to use which**:
- Hashtable for: splatting, lookups, passing options, building request bodies, grouping by key.
- PSCustomObject for: records/rows that will flow through the pipeline, be displayed, exported to CSV/JSON, or have dot-access semantics.

**Conversions**:
```powershell
# hashtable → PSCustomObject
$obj = [PSCustomObject]$ht

# PSCustomObject → hashtable
$ht = @{}
$obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
```

### PS4 — Medium
**Answer:**
PowerShell distinguishes two kinds of errors:

- **Terminating errors** stop the current pipeline and propagate up. Thrown via `throw`, `$PSCmdlet.ThrowTerminatingError()`, a .NET exception in a cmdlet, or a non-terminating error promoted by `-ErrorAction Stop`. Caught by `try/catch`/`trap`.
- **Non-terminating errors** are written to the error stream (`$Error`, stream 2) but execution continues (e.g., `Get-ChildItem` on a folder containing one unreadable file). By default `try/catch` does **not** catch these.

**`-ErrorAction`** (common parameter, alias `-ea`) overrides error behavior *per call*:
- `Continue` (default) — write error and keep going.
- `Stop` — convert to a terminating error. Now `try/catch` works.
- `SilentlyContinue` — suppress and keep going.
- `Ignore` — suppress and don't even add to `$Error`.
- `Inquire` — prompt.

**`$ErrorActionPreference`** — session-wide default (`Continue` by default). Set to `Stop` in scripts that want strict error handling (combined with `Set-StrictMode`).

**`try { } catch { } finally { }`** — catches *terminating* errors. Inside `catch`, `$_` (or `$PSItem`) is an `ErrorRecord`. You can filter by exception type:
```powershell
try {
    Get-Content 'c:\missing.txt' -ErrorAction Stop
} catch [System.IO.FileNotFoundException] {
    Write-Warning "file not found"
} catch {
    Write-Error "other error: $($_.Exception.Message)"
} finally {
    # always runs
}
```

**Interaction**:
1. A cmdlet emits a non-terminating error.
2. Its `-ErrorAction` (or, if unset, `$ErrorActionPreference`) decides what to do.
3. If the effective action is `Stop`, the error becomes terminating and unwinds to the nearest `try/catch` (or ends the pipeline).
4. If not `Stop`, the error is written to the error stream; `$Error[0]` holds the latest record; execution continues.

Use `-ErrorAction Stop` on calls you want to catch, and set `$ErrorActionPreference = 'Stop'` at script top for "fail fast" behavior.

### PS5 — Medium
**Answer:**
**Splatting** is a way to pass a collection of parameters to a cmdlet using a hashtable (for named parameters) or array (for positional), using `@name` instead of `$name` in the call:

```powershell
$params = @{
    Path        = 'C:\data'
    Recurse     = $true
    Filter      = '*.log'
    ErrorAction = 'Stop'
}
Get-ChildItem @params
```

PowerShell unpacks the hashtable into `-Path C:\data -Recurse -Filter *.log -ErrorAction Stop`. Each key/value pair becomes one `-Key Value` pair. For switch parameters set the value to `$true`/`$false`.

Array splatting covers positional args:
```powershell
$args = 'source.txt', 'dest.txt'
Copy-Item @args
```

**Why splatting**:
- Avoids monster long lines (readability).
- Lets you build parameter sets conditionally:
  ```powershell
  $p = @{ Path = $file }
  if ($recurse) { $p.Recurse = $true }
  Get-ChildItem @p
  ```
- Facilitates forwarding arguments between wrapper functions.

**vs passing a hashtable as a single value**:
```powershell
Get-ChildItem -Path $params   # WRONG — treats the whole hashtable as -Path
Get-ChildItem @params         # RIGHT — unpacks into named parameters
```
The `@` sigil vs `$` is the signal to PowerShell's parameter binder to unpack. Without it, the hashtable is just one object and probably binds to the first positional parameter (or fails).

### PS6 — Medium
**Answer:**
**PowerShell remoting** executes commands on a remote computer and streams serialized objects back. Built on top of WS-Management (WinRM) on Windows and, since PowerShell 6+, optionally OpenSSH.

- **`Invoke-Command -ComputerName host -ScriptBlock { ... }`** — sets up an *ephemeral* session, runs the script block (in parallel across multiple computers if you pass a list), and returns the results. Good for fan-out and automation:
  ```powershell
  Invoke-Command -ComputerName srv1,srv2,srv3 -ScriptBlock { Get-Service bits }
  ```
  Can also accept `-Session` to reuse a persistent session or `-AsJob` for background.

- **`Enter-PSSession -ComputerName host`** — opens an *interactive* session where your prompt is now remote; every command runs on the remote machine until `Exit-PSSession`. Good for troubleshooting, not for scripts.
  ```powershell
  Enter-PSSession -ComputerName srv1
  [srv1]: PS> Get-Service bits
  [srv1]: PS> exit
  ```

**Protocols**:
- **WinRM** (Windows default): HTTP/5985 or HTTPS/5986, SOAP-based, Kerberos/NTLM auth, configured with `Enable-PSRemoting`, `winrm quickconfig`. Windows-only on the listener side.
- **SSH** (PowerShell 6+, cross-platform): uses OpenSSH; specify `-HostName` and `-UserName` or `-SSHTransport`. Works to/from Linux and macOS. Required for PSRemoting between non-Windows hosts.

Related: `New-PSSession` creates a persistent session you can pass via `-Session` to `Invoke-Command`/`Enter-PSSession` (avoids reconnection overhead). Results cross the wire via CLIXML serialization — complex objects become "deserialized" property bags on the client side (no live methods).

### PS7 — Hard
**Answer:**
```powershell
function Get-Items {
    $result = @()
    $result += "one"
    return $result
}
$x = Get-Items
$x.GetType().Name   # String   ← NOT Object[]
```

**Why**: PowerShell functions return *everything they emit* to the success pipeline, and the **pipeline unwraps single-element collections** into their lone member. The array `@('one')` entering the pipeline becomes just the string `'one'` on the receiving end. `return` is not special — it's just `$result; return` — the unwrapping happens at the function boundary.

**Zero items**:
```powershell
function Get-Items {
    $result = @()
    return $result
}
$x = Get-Items
$x -eq $null        # True  (empty array becomes $null)
```
An empty array goes into the pipeline, produces no elements, so `$x` is `$null`. This is a classic foot-gun.

**Correct patterns** (any of these work):
1. **Force array on the receiving side** with `@(...)`:
   ```powershell
   $x = @(Get-Items)     # always an array (0, 1, or N items), safe to call .Count, index, foreach
   ```
2. **Type-constrain the variable**:
   ```powershell
   [array]$x = Get-Items
   [string[]]$x = Get-Items
   ```
3. **Use `Write-Output -NoEnumerate`** to emit the array as a single object:
   ```powershell
   return ,$result                      # unary comma = 1-element outer array, so inner stays intact
   # or
   Write-Output -NoEnumerate $result
   ```
4. **Return a `[List[T]]`** instead of an array — generics aren't unwrapped:
   ```powershell
   $result = [System.Collections.Generic.List[string]]::new()
   $result.Add('one')
   return ,$result   # still need the comma, or cast at call site
   ```

Best practice: inside functions, just emit objects (`$obj` on its own line) and let callers wrap with `@(...)` when they need to guarantee array semantics. Avoid `$result += ...` patterns entirely — they're O(n²) because arrays are immutable; prefer `[List[T]]`.

### PS8 — Hard
**Answer:**
**`[scriptblock]`** — an unnamed block of PowerShell code wrapped in `{ }`, a first-class value you can store, pass, and invoke later with `&` or `.Invoke()`:
```powershell
$sb = { param($x) $x * 2 }
& $sb 21   # 42
```
Script blocks can accept parameters (`param(...)`), capture no enclosing scope by default (they execute in a fresh scope when invoked with `&`), and can be serialized/sent to remote sessions.

**Function** — a named, scoped unit with advanced features (`[CmdletBinding()]`, parameter attributes, `Begin`/`Process`/`End`, help metadata, discoverability via `Get-Command`). A function defined in your session lives in the function drive (`Function:\`).

Key differences:
- Script blocks are ad hoc; functions are registered and discoverable.
- Script blocks are easier to marshal across session/thread boundaries.
- Functions support the full advanced-function binding surface without extra ceremony.

**Passing a scriptblock to a remote session**:
```powershell
Invoke-Command -ComputerName srv1 -ScriptBlock { Get-Service bits }
```
The block is serialized, sent, and executed remotely. Local variables are **not** captured; use `-ArgumentList` or `$using:`:
```powershell
$svc = 'bits'
Invoke-Command -ComputerName srv1 -ScriptBlock { Get-Service $using:svc }
# or
Invoke-Command -ComputerName srv1 -ScriptBlock { param($name) Get-Service $name } -ArgumentList $svc
```

**The double-hop problem**: when you remote from machine A to B, B uses its network-logon credentials to act on your behalf. If code on B then tries to authenticate *onwards* to machine C (SMB share, another remoting session, SQL with Windows auth), the network logon cannot delegate — by default Kerberos forbids forwarding credentials to prevent credential theft. B has no password for you. C denies access.

**Solutions**:
1. **CredSSP** — `Enable-WSManCredSSP -Role Client -DelegateComputer 'B'` on A and `Enable-WSManCredSSP -Role Server` on B, then `Invoke-Command -Authentication CredSSP -Credential $c`. CredSSP forwards the actual credentials; powerful but has security implications (the credentials live in memory on B), so many enterprises disable it.
2. **Kerberos constrained/resource-based constrained delegation (RBCD)** — configure AD so that B is allowed to delegate to C on behalf of the user. The modern recommendation: no credentials exposed, finer-grained.
3. **Pre-provisioned credentials** — pass a `PSCredential` object as an argument and have the remote side use it explicitly (`Invoke-Command -Credential $using:cred ...`).
4. **Invoke-Command with `-ArgumentList` or `-Session`** to reuse a single hop — avoid the double hop entirely where possible.
5. **JEA / `PSSessionConfiguration -RunAsCredential`** — let the endpoint run as a service account with the right privileges so the caller never needs to delegate.

### PS9 — Easy
**Answer:**
- **`@( ... )`** is the **array subexpression operator**. It runs the expression inside and guarantees the result is an array (wrapping a scalar, returning an empty array if nothing was emitted).
- **`[array]`** is a *type* (alias for `System.Array`, effectively `[object[]]` when used as a cast). You can cast with `[array]$x` or type-constrain `[array]$x = ...`.

**Force a single result into an array**:
```powershell
$x = @(Get-ChildItem C:\maybe-one-file)   # always an array
# or
[array]$x = Get-ChildItem C:\maybe-one-file
# or (unary comma: wrap in a 1-element array; if original is array, this makes a nested one — usually not what you want)
$x = ,(Get-ChildItem ...)
```
The `@(...)` form is idiomatic and safe whether the expression returns 0, 1, or N objects. Without it, a single-result command returns the bare object and `.Count` / indexing can surprise you. (In PS 3.0+ a scalar even supports `.Count` returning 1 and `[0]` returning itself, so this is less painful than it used to be — but structural code like `foreach` over `$null` still bites.)

**Indexing `$null` vs empty array**:
```powershell
$null[0]     # $null (PowerShell returns $null for any index into $null, no error by default)
@()[0]       # $null (index out of bounds on empty array → $null, no error)
```
Both silently produce `$null` in default (non-strict) mode. With `Set-StrictMode -Version 3.0` (or `Latest`), indexing out of bounds or indexing `$null` becomes an error, which is much safer for scripts. Similarly, enumerating `$null` with `foreach` iterates zero times in modern PS; in legacy strict mode or older versions it could be an error.

### PS10 — Easy
**Answer:**
PowerShell comparison operators are **case-insensitive by default** and work on pipelines (they also filter when applied to collections).

- **`-eq` / `-ne`** — equality / inequality. On collections, filters: `1,2,3 -eq 2` → `2`.
- **`-lt -le -gt -ge`** — numeric/string ordering.
- **`-like` / `-notlike`** — wildcard match (`*`, `?`, `[abc]`). Good for filename-style globs: `$name -like '*.log'`.
- **`-match` / `-notmatch`** — regex match. Populates `$Matches` hashtable with captures on success: `'abc123' -match '(\d+)'; $Matches[1]` → `'123'`.
- **`-contains` / `-notcontains`** — **collection contains a scalar**: `1,2,3 -contains 2` → `True`. Does *not* do substring search.
- **`-in` / `-notin`** — **scalar is in a collection** (reverse of `-contains`): `2 -in 1,2,3` → `True`. Added in PS 3.0.
- **`-replace`** — regex replace: `'foo' -replace 'o','0'` → `'f00'`.

**Case-sensitive variants**: prepend `c`: `-ceq`, `-cne`, `-clike`, `-cmatch`, `-ccontains`, `-cin`, etc. Prepending `i` (`-ieq`, `-ilike`) makes the case-insensitivity explicit — useful when your team's style guide requires clarity. The default is "insensitive" precisely because Windows paths, environment variables, and AD are case-insensitive.

**`-contains` vs `-in`** — same operation, operands reversed:
- `$collection -contains $item` — "does this collection contain the item?"
- `$item -in $collection` — "is this item in the collection?"
`-in` often reads more naturally when the scalar is the left-hand focus (`if ($role -in 'admin','owner')`). Both are O(n) linear scans — for large lookups, use a `[hashset]` or `[hashtable]` for O(1) membership.

`-eq` applied to a collection returns the matching elements, not a boolean: `1,2,3,2 -eq 2` → `2,2`. Use `-contains`/`-in` (or `$null -ne ($a -eq $b)`) when you want a boolean.

### PS11 — Easy
**Answer:**
A **module** is a reusable, versioned package of PowerShell functions, cmdlets, variables, aliases, and/or DSC resources, loaded via `Import-Module` or auto-loaded when you call one of its commands (PS 3+).

**Module forms**:
- **Script module (`.psm1`)** — a plain PowerShell file containing functions and code. `Import-Module .\Foo.psm1` runs the file in its own scope and exports functions (by default everything; filtered by `Export-ModuleMember` or the manifest's `FunctionsToExport`).
- **Manifest module (`.psd1`)** — a hashtable file describing the module: version, author, root module (`RootModule = 'Foo.psm1'` or a DLL), required modules, PowerShell version, exported functions/cmdlets/variables/aliases, file list, format/type data. A manifest adds discoverability, versioning, dependency declaration, and signing metadata. `Test-ModuleManifest` validates it.
- **Binary module** — a compiled .NET assembly (`.dll`) containing classes derived from `Cmdlet` or `PSCmdlet`, typically written in C#. Loaded with `Import-Module Foo.dll`. Full speed of .NET, full access to the PowerShell runtime; used for complex cmdlets and performance-critical work.

Modules are discovered via `$env:PSModulePath` (similar to Unix `PATH`), a semicolon/colon-separated list of directories. Each directory contains `ModuleName/ModuleName.psd1` (or `.psm1`).

**`Import-Module`** loads a module into the current session:
```powershell
Import-Module Foo                     # search PSModulePath
Import-Module .\Foo\Foo.psd1          # explicit path
Import-Module Foo -RequiredVersion 1.2.3
Import-Module Foo -Force              # reload
Import-Module Foo -Prefix Bar         # rename exported commands to avoid conflicts
```
Auto-loading (since PS 3) means you usually don't need explicit `Import-Module` in scripts — calling `Get-Foo` triggers it if the command is found in an on-disk module. `Remove-Module` unloads. `Get-Module` lists loaded modules, `Get-Module -ListAvailable` lists installed ones.

### PS12 — Easy
**Answer:**
- **`"..."` (double-quoted string)** — expands `$var`, `$env:X`, `${complex name}`, and, with `$(...)`, full subexpressions. Supports escape sequences with the **backtick** as the escape character (`` `n `` newline, `` `t `` tab, `` `" `` literal quote, `` `$ `` literal dollar, `` `0 `` null). Uses format operator `-f` for composite strings.
  ```powershell
  $name = 'Ada'
  "Hello, $name! Year: $(Get-Date -Format yyyy)"
  # Hello, Ada! Year: 2026
  ```

- **`'...'` (single-quoted string)** — literal. No expansion, no escapes (except `''` to embed a single quote). Use for fixed strings, especially regexes and paths.

**Including expressions in interpolated strings**:
- Simple variable: `"$name"`.
- Property/method: wrap in `$(...)` — this is the *subexpression operator*:
  ```powershell
  "Uppercase: $($name.ToUpper())"
  "Count: $($list.Count)"
  ```
  Just `"$name.ToUpper()"` would give `Ada.ToUpper()` — property access is not interpolated without `$()`.
- Format operator `-f`:
  ```powershell
  '{0} is {1}' -f $name, $age
  ```

**Here-string** — multi-line string literal that ignores embedded quotes. Two flavors:
- **Expanding** (`@"..."@`): expansion rules of double-quoted strings.
  ```powershell
  $text = @"
  Hello, $name.
  Today is $(Get-Date -Format d).
  Path = "C:\Users\$name"
  "@
  ```
- **Literal** (`@'...'@`): rules of single-quoted strings — great for JSON/HTML/SQL templates.
  ```powershell
  $json = @'
  {
      "name": "Ada"
  }
  '@
  ```
Here-string rules: `@"` must be followed by a newline, and the closing `"@` must be at column 0 of its line with nothing before it (not even whitespace).

### PS13 — Easy
**Answer:**
**`Get-Member`** (alias `gm`) reveals the *type* and *members* (properties, methods, events) of the objects coming down the pipeline. It's the universal discovery tool:
```powershell
Get-Process | Get-Member
Get-Service | Get-Member -MemberType Method
'hello' | Get-Member
```
The output lists each member with its kind (`Property`, `Method`, `ScriptProperty`, `NoteProperty`, `AliasProperty`, `Event`) and the defining type. It's how you learn "what can I do with this object?" — always pipe an unfamiliar object to `Get-Member` first.

**Member kinds**:
- **Property** — a real .NET property from the underlying type (e.g., `Process.ProcessName`).
- **Method** — a real .NET method (e.g., `String.ToUpper()`).
- **NoteProperty** — a simple name/value pair added dynamically (this is what `PSCustomObject` literals and `Add-Member -MemberType NoteProperty` produce; they aren't defined on the underlying .NET type).
- **ScriptProperty / ScriptMethod** — dynamic members implemented with a PowerShell script block, attached via the extended type system (`Types.ps1xml`).
- **AliasProperty** — a member that just aliases another (e.g., `Count` → `Length`).

**`Select-Object` vs `Where-Object`** (they are often confused but do totally different things):
- **`Where-Object`** (alias `?`) — **filters rows** (objects). Evaluates a condition per object; keeps those where it is true.
  ```powershell
  Get-Process | Where-Object { $_.WS -gt 200MB }
  Get-Service | Where-Object Status -eq 'Running'   # simplified syntax (PS 3+)
  ```
- **`Select-Object`** (alias `select`) — **projects columns** (properties) and/or limits count. Picks properties, creates new calculated properties, slices with `-First`/`-Last`/`-Skip`, returns distinct with `-Unique`:
  ```powershell
  Get-Process | Select-Object Name, Id, @{Name='MB'; Expression={[math]::Round($_.WS/1MB,1)}} -First 5
  ```
Mnemonic: `Where-Object` filters rows, `Select-Object` picks columns (like SQL `WHERE` vs `SELECT`).

### PS14 — Medium
**Answer:**
PowerShell classes (PS 5.0+, keyword `class`) let you define types with properties, methods, constructors, inheritance, and enums directly in PowerShell:
```powershell
class Animal {
    [string]$Name
    [int]$Age

    Animal([string]$name, [int]$age) {
        $this.Name = $name
        $this.Age = $age
    }

    [string] Describe() { return "$($this.Name) ($($this.Age))" }
}

class Dog : Animal {
    Dog([string]$name, [int]$age) : base($name, $age) {}
    [string] Bark() { return "$($this.Name) says woof" }
}
```
Under the hood they compile to real .NET types and are implemented as such.

**Differences from C# classes / limitations**:
- **Single inheritance only** (like C#), and the base must be another PowerShell class or a .NET class available at parse time.
- **Interface support is limited** — PS 5.1 supports implementing interfaces, but with quirks (methods must exactly match signatures; default interface methods from C# 8+ aren't usable).
- **No `protected`/`internal` visibility** — only implicitly public for methods; `hidden` keyword gives IntelliSense-level hiding but not true access control.
- **Constructors don't support named/optional parameters natively**; you chain with `: base(...)` for inheritance and define overloads for defaults.
- **Type resolution is at parse time** — a class that references a type from a module must be loaded via `using module Foo` (not `Import-Module`), because PS parses scripts before `Import-Module` runs.
- **No generics authoring** (you can *use* generics from .NET, not define generic PS classes).
- **No partial classes, no `static` constructors in the full C# sense**, no operator overloading.
- **Classes are scoped to the file/module** that defines them; exporting them across modules is clunky (requires `using module`).
- **Reloading is painful** — once a class is defined in a session, you can't redefine it without `-Force` reloads or a new session, making iterative development slow.

**When to use a class vs a function**:
- **Use a class** when you need: a strongly typed data record with methods, DSC resources (classes are the modern DSC authoring model), custom .NET-style types to pass between components, implementing interfaces required by external APIs, or encapsulating state with behavior.
- **Use a function** (especially an advanced function with `[CmdletBinding()]`) for almost everything else: tools, pipeline consumers, scripts. Functions get the full PowerShell binding surface (pipelines, parameter sets, ShouldProcess, verbose/debug, help) that classes do not.

Idiom: "Script in functions, model in classes." Most day-to-day scripting needs zero classes; use `[PSCustomObject]` for simple records.

### PS15 — Medium
**Answer:**
An **advanced function** is a PowerShell function that opts into the full cmdlet-style parameter binding engine by adding `[CmdletBinding()]` (or adding parameter attributes like `[Parameter()]`). This transforms it from a script function into something that behaves almost identically to a compiled cmdlet.

```powershell
function Get-WidgetInfo {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='ByName')]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName,
                   ParameterSetName='ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName='ById')]
        [int]$Id,

        [ValidateSet('A','B','C')]
        [string]$Kind = 'A'
    )
    begin   { Write-Verbose 'starting' }
    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Query')) {
            # ... real work ...
        }
    }
    end     { Write-Verbose 'done' }
}
```

**`[CmdletBinding()]` enables**:
- **Common parameters** automatically: `-Verbose`, `-Debug`, `-ErrorAction`, `-ErrorVariable`, `-WarningAction`, `-InformationAction`, `-OutVariable`, `-OutBuffer`, `-PipelineVariable`.
- **`$PSCmdlet`** automatic variable (`WriteVerbose`, `ThrowTerminatingError`, `ShouldProcess`, `ShouldContinue`, `MyInvocation`).
- Strict parameter binding — unknown parameters error instead of going into `$args`.

**`SupportsShouldProcess`** adds the `-WhatIf` and `-Confirm` common parameters automatically and lets you guard destructive operations with `$PSCmdlet.ShouldProcess($target, $action)`, which returns `$false` under `-WhatIf` (so the operation is skipped and logged) and prompts for confirmation when the confirm impact meets the user's preference.

**`DefaultParameterSetName`** designates which parameter set wins when PowerShell can't disambiguate from the supplied arguments. Parameter sets (`ParameterSetName='Foo'` on `[Parameter]` attributes) let one function expose multiple mutually exclusive usage patterns — e.g., "by name" vs "by id".

**`ValueFromPipeline`** binds the whole incoming pipeline object to this parameter. **`ValueFromPipelineByPropertyName`** binds to a property of the incoming object with the same name (or listed in `Aliases`). Together they make a function act like a pipeline cmdlet.

**Block semantics — `begin`, `process`, `end`** (and PS 7.3+ `clean`):
- **`begin`** — runs **once**, before any pipeline input is received. Use for setup, opening connections.
- **`process`** — runs **once per input object**. This is where pipeline parameters are bound to their current value. For non-pipeline calls, `process` still runs once.
- **`end`** — runs **once** after all input has been processed. Use for teardown, final output.
- **`clean`** — guaranteed cleanup even if the pipeline was cancelled (PS 7.3+).

If you omit `begin`/`process`/`end` blocks and just write code in the function body, it's implicitly the `end` block — which means pipeline input isn't streamed, it's all collected first. To process streamed input, always use an explicit `process { }` block.

### PS16 — Medium
**Answer:**
PowerShell **providers** expose disparate data stores through a uniform drive/path abstraction. Any provider-aware cmdlet (`Get-Item`, `Get-ChildItem`, `Get-Content`, `Set-Content`, `Test-Path`, `Remove-Item`, `New-Item`, `Get-ItemProperty`, `Set-Location`, etc.) can operate across any provider using `<Drive>:\<path>` syntax.

Standard built-in providers:
- **FileSystem** — disks (`C:`, `D:`, etc.).
- **Registry** — Windows registry (`HKLM:`, `HKCU:`).
- **Environment** — process env vars (`Env:`).
- **Variable** — session variables (`Variable:`).
- **Function** — loaded functions (`Function:`).
- **Alias** — aliases (`Alias:`).
- **Certificate** — cert stores (`Cert:`).
- **WSMan** — WS-Management configuration.

Discover with `Get-PSProvider` and `Get-PSDrive`.

Because `Get-ChildItem` (alias `dir`, `ls`) dispatches to whichever provider owns the drive, the same cmdlet lists files, registry subkeys, variables, or certificates:
```powershell
Get-ChildItem C:\Windows          # files
Get-ChildItem Env:                # env vars
Get-ChildItem Function:           # functions in the session
Get-ChildItem Cert:\LocalMachine\My   # certificates
```

**Registry like a filesystem**:
```powershell
Set-Location HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion
Get-ChildItem                          # list subkeys (like dirs)
Get-ItemProperty .                     # list values of this key (values are "properties", not children)
Get-ItemProperty . -Name ProductName
(Get-ItemProperty . -Name BuildLab).BuildLab

New-Item -Path HKCU:\Software\MyApp -Force
New-ItemProperty -Path HKCU:\Software\MyApp -Name Version -Value '1.0' -PropertyType String
Remove-Item -Path HKCU:\Software\MyApp -Recurse
```
Key distinction: in the registry provider, **subkeys are children** (enumerated by `Get-ChildItem`) but **values are properties** of a key (read/written with `Get-ItemProperty`/`Set-ItemProperty`/`New-ItemProperty`). This is the only slightly tricky part — everything else reuses the same cmdlets you'd use on the filesystem.

Custom providers can be written in C#; examples include SQL Server's `SQLSERVER:`, Git providers, etc.

### PS17 — Hard
**Answer:**
**Runspace** — the fundamental unit of PowerShell execution: a host for the engine state (session state, variables, modules, loaded types). Each runspace is single-threaded: commands run sequentially in it. A PS session *is* a runspace. You create one directly with `[runspacefactory]::CreateRunspace()` or `[powershell]::Create()` (which creates an implicit runspace).

**`[powershell]`** — a pipeline builder bound to a runspace. You add commands/scripts and call `.Invoke()` (synchronous) or `.BeginInvoke()` (async). Multiple `[powershell]` objects can share a runspace pool.

**RunspacePool** (`[runspacefactory]::CreateRunspacePool(min, max)`) — a pool of runspaces for parallel reuse. Instead of creating N runspaces by hand, you open the pool and assign each `[powershell]` object to it (`ps.RunspacePool = $pool`); up to `max` runs concurrently.

**Thread safety**:
- Each runspace is single-threaded internally — no concurrency inside one runspace.
- Variables and modules are **per-runspace** — modifying `$global:x` in one runspace is invisible to another.
- Sharing state across runspaces requires thread-safe .NET collections (`[System.Collections.Concurrent.ConcurrentBag[T]]`, `[System.Collections.Concurrent.ConcurrentDictionary[K,V]]`) or explicit locks (`[System.Threading.Monitor]`).
- The host's output synchronization (console writing) is the host's problem; data collected via `BeginInvoke(inputs, outputs)` into a `PSDataCollection` is thread-safe.

**`ForEach-Object -Parallel` (PS 7.0+)** — the high-level, idiomatic approach. Creates a runspace pool under the covers and dispatches each iteration onto it:
```powershell
1..20 | ForEach-Object -Parallel {
    Start-Sleep -Seconds 1
    "Done $_ on thread $([Threading.Thread]::CurrentThread.ManagedThreadId)"
} -ThrottleLimit 5
```
- Pass variables with `$using:var` (captured by value, serialized).
- `-ThrottleLimit` caps concurrency.
- `-AsJob` returns a job object.
- Each iteration runs in a fresh runspace scope — modules/loaded types from the parent are **not** available unless re-imported or loaded via `-UseNewRunspace`/script prelude.
- Overhead is non-trivial; don't use it for many short tasks (start-up cost dominates).

**Manual runspace management** — still necessary when you need:
- A **persistent, reusable** pool across multiple jobs.
- Fine control over `InitialSessionState` (pre-import modules, variables, types).
- Working in Windows PowerShell 5.1 (no `-Parallel`).
- Passing live objects without `$using:` serialization.

```powershell
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$iss.ImportPSModule('MyModule')
$pool = [runspacefactory]::CreateRunspacePool(1, 10, $iss, $Host)
$pool.Open()

$jobs = foreach ($i in 1..20) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    $null = $ps.AddScript({ param($n) "processed $n" }).AddArgument($i)
    [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
}
$results = foreach ($j in $jobs) {
    $j.PS.EndInvoke($j.Handle)
    $j.PS.Dispose()
}
$pool.Close(); $pool.Dispose()
```

Trade-offs: `ForEach-Object -Parallel` is far simpler; manual runspaces win on reuse, startup cost, and PS 5.1 support.

### PS18 — Hard
**Answer:**
**PSScriptAnalyzer** (module `PSScriptAnalyzer`, cmdlet `Invoke-ScriptAnalyzer`) is the official PowerShell **static analyzer/linter**. It parses scripts and modules (without executing them) using the PowerShell AST and applies a catalog of rules that check for stylistic issues, common bugs, security smells, and compatibility problems.

```powershell
Install-Module PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path .\src -Recurse
Invoke-ScriptAnalyzer -Path .\foo.ps1 -Severity Warning,Error
```

**Rules** — each is a named check such as:
- `PSAvoidUsingCmdletAliases` — don't use `gci`, `%`, `?` in scripts.
- `PSUseApprovedVerbs` — function names must use verbs from `Get-Verb`.
- `PSAvoidUsingPlainTextForPassword` — don't declare a `[string]$Password`; use `[securestring]` or `[PSCredential]`.
- `PSUseDeclaredVarsMoreThanAssignments` — catches unused variables.
- `PSUseShouldProcessForStateChangingFunctions` — verbs like `Set-`, `Remove-` should support `-WhatIf`/`-Confirm`.
- `PSAvoidUsingInvokeExpression` — `Invoke-Expression` is dangerous.
- `PSUseConsistentIndentation`, `PSUseConsistentWhitespace` — formatter rules.
- `PSAvoidUsingWriteHost` (with caveats).

**Severity levels**: `Information`, `Warning`, `Error`, plus `ParseError`. You filter with `-Severity` and decide which levels break your build.

**Custom rules**: you can write your own rules as .NET DLLs (`IScriptRule`) or PowerShell modules following the `AstVisitor` pattern, and load them with `Invoke-ScriptAnalyzer -CustomRulePath .\MyRules`. Useful for team-specific conventions.

**Configuration / suppression**:
- Project-wide settings via a `PSScriptAnalyzerSettings.psd1` hashtable (`-Settings path`), letting you `IncludeRules`, `ExcludeRules`, tweak per-rule options (indentation width, PSAvoidLongLines, compatible PowerShell/OS/modules).
- Per-file or per-function suppression with `[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute]`:
  ```powershell
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
      'PSAvoidUsingWriteHost', '', Justification = 'interactive tool, direct console output wanted'
  )]
  param()
  ```
- Line-level comments (`# PSSA ...`) aren't a thing — you suppress at function/file scope via the attribute.

**CI/CD integration**:
- GitHub Actions: `Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error | ForEach-Object { ... }`, fail the step if any records are returned, or use the community action `microsoft/psscriptanalyzer-action`.
- Azure DevOps: run in a `PowerShell@2` task, convert results to SARIF or NUnit XML and publish.
- Pre-commit: via the `pre-commit-powershell` hook or a git hook that runs `Invoke-ScriptAnalyzer -EnableExit` (non-zero exit on findings above threshold).
- Editor: built into the PowerShell VS Code extension (shows warnings inline; runs Format Document via PSSA's formatter rules).

Typical enforcement: fail CI on `Error` and `Warning`, let `Information` slide, pin the rule set in a versioned `PSScriptAnalyzerSettings.psd1` so all contributors lint the same way.

### PS19 — Hard
**Answer:**
When code crosses a boundary — remoting, background job, parallel foreach — it leaves the current runspace, so it can't see your local variables automatically. PowerShell offers two mechanisms:

**`$using:`** (PS 3.0+) — inside a script block destined for another runspace, `$using:localVar` copies the local variable's value *into* the remote script block's scope.
```powershell
$host = 'srv1'
Invoke-Command -ComputerName $host -ScriptBlock { Get-Service $using:host }
Start-Job -ScriptBlock { param() "host is $using:host" } | Receive-Job -Wait -AutoRemoveJob
1..10 | ForEach-Object -Parallel { "$using:host : $_" }
```
- Value is captured **once**, at the moment the scriptblock is sent, via CLIXML serialization.
- Works with `Invoke-Command`, `Start-Job`, `Start-ThreadJob`, `ForEach-Object -Parallel`, `Invoke-Command -Session`.
- You cannot assign to `$using:x` — it's read-only.
- Complex live objects (`Process`, DB connections, runspaces) can't be serialized and will arrive as inert property bags.

**`-ArgumentList` / `$args`** — explicit argument passing:
```powershell
Invoke-Command -ComputerName srv1 -ScriptBlock { param($h) Get-Service $h } -ArgumentList $host
Start-Job -ScriptBlock { param($h) "$h" } -ArgumentList $host
```
- Passed positionally; the script block declares `param(...)`.
- Also serialized via CLIXML but explicit (arguably clearer for long-lived code and matches the "parameters on function" mental model).

**`ForEach-Object -Parallel`** accepts only `$using:` (no `-ArgumentList`). Background jobs accept both. `Start-ThreadJob` (fast, in-proc) also accepts both.

**Serialization limits — CLIXML**:
- All cross-runspace data uses CLI XML (`System.Management.Automation.PSSerializer`).
- Primitive types, `DateTime`, `TimeSpan`, `Uri`, `Guid`, `Version`, `string`, arrays, hashtables, and `PSCustomObject` **round-trip with full fidelity**.
- **Rich .NET objects** (Process, FileInfo, etc.) are serialized as **property bags** — you get a `Deserialized.*` object with values but *no methods* and no live reference. Example: after remoting, `$proc | Stop-Process` won't work because the deserialized Process has no `Kill()` method; you'd need to call `Stop-Process -Id $proc.Id` explicitly.
- **Default depth is 1** for `Invoke-Command` and similar (configurable per session via `PSSessionConfiguration` or with `[PSSerializer]::Serialize(obj, depth)`). Nested objects beyond the depth are converted to strings. Symptoms: nested hashtables come back with `System.Collections.Hashtable` as the value instead of data.
- **Circular references** are truncated.
- **Delegates, live handles, and runspaces** cannot be sent at all.

Practical implications:
1. Treat remoted/parallelized data as *immutable value records*.
2. Do any method calls on the remote side before returning.
3. For deep objects, increase the serialization depth on the `PSSessionConfiguration` (`Register-PSSessionConfiguration -PSMaximumReceivedObjectSizeMB` / `SessionType` XML), or flatten to a `[PSCustomObject]` before returning.
4. Watch for performance cliffs: huge arrays cost real network + CPU to serialize both ways.

Rule of thumb: prefer `$using:` for brevity; use `param(...) + -ArgumentList` in reusable scriptblocks and for job-style code; never return live .NET objects you need to call methods on, return plain records.

### PS20 — Hard
**Answer:**
**Desired State Configuration (DSC)** is a declarative configuration-management platform built into PowerShell. You describe the *desired state* of a machine (services, files, registry keys, features, custom resources), compile it to a MOF document, and an agent applies and continuously enforces it.

**Configurations** — a DSC-specific language construct (`Configuration Name { Node 'host' { ... } }`) that, when invoked, compiles node blocks into `.mof` files, one per target node:
```powershell
Configuration WebServer {
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Node 'web01' {
        WindowsFeature IIS {
            Name   = 'Web-Server'
            Ensure = 'Present'
        }
        File Default {
            DestinationPath = 'C:\inetpub\wwwroot\index.html'
            Contents        = '<h1>hello</h1>'
            Ensure          = 'Present'
            DependsOn       = '[WindowsFeature]IIS'
        }
    }
}
WebServer -OutputPath .\out
Start-DscConfiguration -Path .\out -Wait -Verbose
```

**Resources** — the building blocks, each a PS module implementing three operations:
- `Get-TargetResource` — report current state.
- `Test-TargetResource` — return `$true` if already compliant.
- `Set-TargetResource` — bring the system into compliance.
Built-in resources cover `File`, `Registry`, `Service`, `User`, `Group`, `WindowsFeature`, `Script`, `Package`, `Archive`, etc. Community/vendor resources live in the Gallery (e.g., `xWebAdministration`, `NetworkingDsc`). Since PS 5, class-based DSC resources are the recommended authoring model, replacing script-based ones.

**Local Configuration Manager (LCM)** — the DSC engine running on each managed node. It receives MOFs, applies them, then enforces at a **consistency interval** (default 15 min) using `Test` → `Set` if drift is detected. Configurable via `[DSCLocalConfigurationManager()]` meta-configurations: `RefreshMode` (Push vs Pull), `ConfigurationMode` (`ApplyOnly`, `ApplyAndMonitor`, `ApplyAndAutoCorrect`), pull-server URLs, credential handling, reboot behavior. `Get-DscLocalConfigurationManager` inspects it.

**Push vs Pull**:
- **Push** — you run `Start-DscConfiguration -Path ...` from your workstation/CI, LCM applies immediately.
- **Pull** — nodes poll a pull server (HTTP/SMB) for their configuration and resource modules, ideal at scale. Microsoft-hosted pull server: Azure Automation State Configuration.

**Windows PowerShell 5.1 vs PowerShell 7+**:
- **DSC 1.1** shipped with Windows PowerShell 5.1 and is tightly tied to the MOF compiler, the WMI/CIM-based LCM, and Windows. It still works on Windows Server.
- **DSC 2.x** (project *DSCv2* / `PSDesiredStateConfiguration` 2.0.5+) decouples DSC from the inbox LCM: configurations are compiled by the new module, and it runs cross-platform (Windows, Linux, macOS) on PS 7+. The class-based resource model is emphasized.
- **DSCv3** (currently preview, Microsoft) is a complete rewrite: a standalone cross-platform engine (`dsc` binary written in Rust), language-agnostic resources (PowerShell, Bash, JSON-schema-driven), JSON/YAML instead of MOF. It's the direction Microsoft is pushing; still new as of 2026.
- Azure **Machine Configuration** (formerly Azure Policy Guest Configuration) is the Azure-hosted successor to Azure Automation DSC — it uses the newer engine under the hood.

**What replaced DSC in modern IaC?** In practice, the industry largely moved to:
- **Ansible** (agentless, YAML, huge module ecosystem including `ansible.windows.*` and PowerShell-based modules) — the most common replacement for mixed fleets.
- **Chef / Puppet / Salt** — still used for legacy agents; similar declarative model.
- **Terraform / Pulumi / Bicep** — infrastructure provisioning (not OS-level config) but often paired with cloud-init or VM extensions instead of DSC.
- **Azure Machine Configuration / Azure Policy Guest Configuration** — Microsoft's managed successor to Azure Automation DSC for Azure VMs and Arc-enabled servers, still uses DSC under the hood but fronted by Azure Policy.
- **DSCv3** is trying to win back this space by being lightweight, cross-platform, and IaC-toolable.

Azure Automation DSC was officially **retired** in 2023 for new onboarding, with Machine Configuration as the successor — a strong signal that classic (v1) DSC is legacy, and most new Windows configuration work happens in Ansible, Bicep + custom script extensions, or Machine Configuration.
