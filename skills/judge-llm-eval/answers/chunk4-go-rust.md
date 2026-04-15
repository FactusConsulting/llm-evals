# Go + Rust Knowledge Test Suite — Answers

---

## Section 1: Go (G1–G20)

### G1 — Easy
**Answer:**
An **array** `[N]T` has a fixed compile-time length that is part of its type; arrays are value types and are copied on assignment/function call. A **slice** `[]T` is a descriptor `{ptr, len, cap}` that views a contiguous region of an underlying array; slices are reference-like (the header is copied, but the backing array is shared).

When `append` is called on a slice whose `len == cap`, the runtime allocates a **new, larger backing array** (growth is roughly ~2x for small slices, ~1.25x for larger ones in modern Go), copies the existing elements into it, appends the new element(s), and returns a new slice header pointing at the new array. The old backing array is left untouched — other slices that still point at it are unaffected. This is why you must always write `s = append(s, x)`.

```go
a := [3]int{1, 2, 3}       // array, length is part of type
s := []int{1, 2, 3}        // slice
s = append(s, 4)           // may reallocate if len == cap
```

### G2 — Easy
**Answer:**
`var x int` is a **declaration** that creates `x` with its zero value (`0` for `int`). It works at package scope and function scope, and you can declare without initializing.

`x := 0` is a **short variable declaration** that both declares and initializes; the type is inferred from the right-hand side. It requires an initializer and is only legal **inside a function** (not at package scope). It also requires at least one new variable on the left; you cannot use `:=` to reassign existing variables only, and you cannot use it for struct fields or package-level variables.

```go
var x int            // package or function scope, zero value
y := 0               // function scope only, must have RHS
```

### G3 — Medium
**Answer:**
A **goroutine** is a lightweight, user-space thread managed by the Go runtime. It starts with a small (~2 KiB) growable stack and is multiplexed onto OS threads, so you can run hundreds of thousands of them. An OS thread, by contrast, has a large fixed stack (often 1–8 MiB), is scheduled by the kernel, and context-switching is more expensive.

The Go scheduler uses the **GMP model**:
- **G** — a goroutine (stack, PC, scheduling state).
- **M** — an OS thread ("machine") that actually runs code.
- **P** — a "processor"; a logical scheduling context that holds a runnable-G queue. The number of Ps defaults to `GOMAXPROCS` (usually the number of CPU cores).

An M must acquire a P to run Go code. Each P has a local runqueue; when it empties, the scheduler tries to steal work from other Ps (work-stealing) or pull from the global runqueue. On blocking syscalls, the M detaches from its P so another M can take over that P and keep running goroutines.

### G4 — Medium
**Answer:**
A **channel** is a typed, thread-safe conduit for sending values between goroutines. Created with `make(chan T)` (unbuffered) or `make(chan T, N)` (buffered).

- **Unbuffered channel**: send and receive are synchronous — a send blocks until another goroutine is ready to receive, and vice versa. This gives "happens-before" synchronization.
- **Buffered channel**: `make(chan T, N)` holds up to `N` values. A send blocks only when the buffer is full; a receive blocks only when the buffer is empty.

When you send to a **full** buffered channel, the sending goroutine **blocks** until a receiver frees a slot. Sending on a **closed** channel panics; receiving from a closed channel returns the zero value immediately (and `v, ok := <-ch` yields `ok == false`).

```go
ch := make(chan int, 2)
ch <- 1
ch <- 2
// ch <- 3  // would block until someone receives
```

### G5 — Medium
**Answer:**
The `context` package carries cancellation signals, deadlines, and request-scoped values across API boundaries and goroutines. It is the idiomatic way to propagate "stop what you're doing" to downstream work.

```go
package main

import (
    "context"
    "fmt"
    "net/http"
    "time"
)

func main() {
    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
    defer cancel()

    req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://example.com", nil)
    if err != nil {
        fmt.Println("new request:", err)
        return
    }

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        fmt.Println("do:", err) // ctx deadline exceeded surfaces here
        return
    }
    defer resp.Body.Close()
    fmt.Println("status:", resp.Status)
}
```

If the request takes longer than 2 seconds, the context's deadline fires, the transport cancels the in-flight request, and `Do` returns an error wrapping `context.DeadlineExceeded`.

### G6 — Medium
**Answer:**
Go uses **structural (implicit) interface satisfaction**: a type `T` satisfies interface `I` if its method set contains every method `I` declares. There is no `implements` keyword; the relationship is checked by the compiler at the use site. This decouples implementations from interface definitions — the interface can be declared in the consumer's package, which enables "accept interfaces, return concrete types."

Java/C# interfaces are **nominal**: a class must explicitly declare `implements I` / `: I`. A class cannot retroactively satisfy an interface declared elsewhere.

The empty interface `interface{}` (aliased as `any` in Go 1.18+) has zero methods, so every type satisfies it. It's powerful because it enables heterogeneous collections and generic-ish APIs (pre-generics), but dangerous because:
- You lose static type safety — you need type assertions or type switches to get the value back, which can panic or fail at runtime.
- It encourages `map[string]any`-style dynamic typing that the compiler can't verify.
- Since Go 1.18, generics (`[T any]`) are preferable for most cases that historically used `interface{}`.

### G7 — Hard
**Answer:**
The code has a **data race**: the main goroutine reads `ready` and `data` while another goroutine writes them, with **no synchronization**. Under the Go memory model, reads in one goroutine are only guaranteed to observe writes from another goroutine if there's a synchronizing operation (channel op, mutex, `sync/atomic`, `sync.Once`, etc.) establishing a happens-before relationship. Without that, the compiler or CPU is free to reorder the writes, cache values in registers, or never propagate them. The main goroutine may:
- Spin forever (never see `ready == true`).
- See `ready == true` but `data == ""` (writes reordered/torn).
- Tear the string read (non-atomic).

`go run -race` will flag it.

**Correct alternatives:**

1. **Channel** (idiomatic):
```go
done := make(chan struct{})
var data string

go func() {
    data = "hello"
    close(done)
}()

<-done
fmt.Println(data)
```

2. **`sync.WaitGroup`**:
```go
var wg sync.WaitGroup
var data string
wg.Add(1)
go func() {
    defer wg.Done()
    data = "hello"
}()
wg.Wait()
fmt.Println(data)
```

3. **Mutex**:
```go
var mu sync.Mutex
var ready bool
var data string

go func() {
    mu.Lock()
    data = "hello"
    ready = true
    mu.Unlock()
}()

for {
    mu.Lock()
    r := ready
    d := data
    mu.Unlock()
    if r {
        fmt.Println(d)
        return
    }
    runtime.Gosched()
}
```

4. **`sync/atomic`** for the flag plus a happens-before-ordered payload.

### G8 — Hard
**Answer:**
- **`sync.Mutex`**: a plain mutual-exclusion lock. Only one goroutine may hold it at a time, whether reading or writing.
- **`sync.RWMutex`**: a readers–writer lock. Any number of readers can hold `RLock` concurrently, but a `Lock` (writer) excludes all other readers and writers. Use it when reads vastly outnumber writes and the critical section is non-trivial. For short critical sections, the extra bookkeeping of `RWMutex` often makes it **slower** than a plain `Mutex`.
- **`sync.Map`**: a concurrent map optimized for two specific access patterns: (1) keys are written once and read many times, or (2) disjoint goroutines write disjoint key sets. It uses an atomic read-mostly "read map" plus a write-protected "dirty map" and promotes entries lazily. It has no `len`, no type safety (keys/values are `any`), and is slower than `map + Mutex` for write-heavy workloads with high key churn.

**Rule of thumb**: default to `map[K]V` guarded by a `sync.Mutex` (or `RWMutex` if reads dominate and critical sections are longer than a few ns). Reach for `sync.Map` only after profiling shows contention on the mutex with one of its favored access patterns.

### G9 — Hard
**Answer:**
Go modules are the dependency-management system (Go 1.11+). A module is a tree of Go packages rooted at a `go.mod` file, with a module path and explicit dependency versions.

- **`go.mod`** declares the module path, the Go version, and the **direct** dependency requirements (with the minimum acceptable version of each). It may also contain `replace`, `exclude`, and `retract` directives.
- **`go.sum`** is a lockfile-like manifest of cryptographic hashes (`h1:...`) for **every** module version (direct and transitive) that the build has ever resolved, used to verify integrity against the Go checksum database (`sum.golang.org`).

**`go mod tidy`** rewrites `go.mod` and `go.sum` so they match what the source actually imports: it adds missing requirements, removes unused ones, and prunes stale `go.sum` entries.

**Minimum Version Selection (MVS)**: Go's deterministic, no-SAT-solver dependency algorithm. For each module, it builds the set of all minimum versions requested (by the main module and, transitively, by each dependency's `go.mod`) and picks the **maximum of those minimums**. There is no "latest compatible" or backtracking — the build list is fully determined by the `go.mod` graph, which makes it reproducible without a separate lockfile and without surprising upgrades.

### G10 — Medium
**Answer:**
A `defer` statement schedules a function call to run when the surrounding **function returns** (normally or via panic). Deferred calls run in **LIFO** order — the most recently deferred call runs first. Arguments to the deferred call are **evaluated at the point of the `defer` statement**, not when the call actually runs.

```go
func f() {
    defer fmt.Println("1")
    defer fmt.Println("2")
    defer fmt.Println("3")
}
// prints: 3, 2, 1
```

**Common gotcha — `defer` in a loop**: defers accumulate for the **whole function**, not the loop iteration. This leaks resources until the function returns:

```go
// BAD: all files stay open until f returns
for _, name := range names {
    f, err := os.Open(name)
    if err != nil { return err }
    defer f.Close()
    // work with f
}
```

Fix by extracting the loop body into its own function (so `defer` scopes to each call) or closing explicitly:

```go
for _, name := range names {
    if err := process(name); err != nil { return err }
}

func process(name string) error {
    f, err := os.Open(name)
    if err != nil { return err }
    defer f.Close()
    // ...
    return nil
}
```

### G11 — Easy
**Answer:**
A pointer is a value holding the memory address of another value of a specific type. `*T` is "pointer to `T`"; `&x` takes the address of `x`; `*p` dereferences.

The **zero value** of a pointer is `nil`. Dereferencing a `nil` pointer panics with `runtime error: invalid memory address or nil pointer dereference`.

You create a pointer to a struct literal with the `&T{...}` shorthand:

```go
type Point struct{ X, Y int }

p := &Point{X: 1, Y: 2}   // *Point
fmt.Println(p.X)          // auto-dereferences
```

Equivalent forms: `new(Point)` (zero-valued), or `var p Point; pp := &p`.

### G12 — Easy
**Answer:**
`init()` is a special, parameterless, no-return function used for package initialization. It runs **once per package**, automatically, **after** all package-level variable initializers have evaluated and **before** `main` starts. Imported packages are initialized before the package that imports them (transitive, in dependency order).

A package **can** have multiple `init()` functions — even multiple per file. Within a single file they execute in the order they appear. Across files in the same package, they execute in the order the compiler presents the files to the linker, which is the order given by `go build` / `go tool compile` — typically alphabetical filename order — but the Go spec only guarantees "some order" across files. You cannot call `init()` explicitly, and you cannot take its address.

### G13 — Easy
**Answer:**
Both allocate, but they do different things:

- **`new(T)`** allocates zeroed storage for a `T` and returns a `*T` pointing at it. Works for **any type**. `new(int)` gives you a `*int` pointing to `0`.
- **`make(T, args...)`** initializes (not just allocates) a **slice, map, or channel** and returns a `T` (not `*T`). These three types are built on runtime data structures (slice header, hmap, hchan) that need more than zeroed memory to be usable — `make` wires them up.

```go
p := new(int)                 // *int -> 0
s := make([]int, 0, 10)       // []int, len=0, cap=10
m := make(map[string]int)     // empty map
ch := make(chan int, 4)       // buffered channel
```

You would **not** use `new` for slices/maps/channels (you'd get a pointer to a nil header), and you **cannot** use `make` for anything else.

### G14 — Easy
**Answer:**
Go has no exceptions; errors are ordinary values returned as the last return value. The `error` interface is:

```go
type error interface {
    Error() string
}
```

Any type with an `Error() string` method satisfies it. The idiomatic pattern is:

```go
f, err := os.Open(name)
if err != nil {
    return fmt.Errorf("open %s: %w", name, err)  // %w wraps
}
defer f.Close()
```

**`==`** only checks whether two error values are the exact same (often sentinel) error, and does not unwrap.

**`errors.Is(err, target)`** walks the wrap chain (via `Unwrap()`) and reports whether **any error in the chain** equals `target` or reports `Is(target) == true`. Use it for sentinel comparisons like `errors.Is(err, io.EOF)`.

**`errors.As(err, &target)`** walks the chain looking for an error that can be assigned to `*target` (a specific error **type**) and, if found, assigns it and returns `true`. Use it to extract a structured error, e.g. `var pe *os.PathError; if errors.As(err, &pe) { ... }`.

### G15 — Easy
**Answer:**
Go's built-in composite types and their zero values:

| Type | Example | Zero value |
|---|---|---|
| Array | `[3]int` | all elements zero-valued (`[3]int{0,0,0}`) |
| Slice | `[]int` | `nil` (len 0, cap 0, no backing array) |
| Map | `map[string]int` | `nil` (reads return zero value; writes **panic**) |
| Channel | `chan int` | `nil` (send/recv block forever; close panics) |
| Struct | `struct{A int; B string}` | every field at its zero value |
| Pointer | `*T` | `nil` |
| Interface | `io.Reader` | `nil` (nil type **and** nil value) |
| Function | `func()` | `nil` |

A nil slice is safe to `append` to and `range` over; a nil map is safe to read but not write; a nil channel blocks forever on both send and receive (useful for disabling `select` cases).

### G16 — Medium
**Answer:**
A **race condition** (specifically a **data race**) occurs when two or more goroutines access the same memory location **concurrently**, at least one access is a write, and there is no synchronization ordering the accesses. The result is undefined behavior — torn reads, lost writes, stale values.

**`-race`** (passed to `go run`, `go test`, `go build`) enables the race detector. It instruments every memory access and synchronization primitive at compile time and uses a happens-before algorithm (based on ThreadSanitizer / vector clocks) at runtime to detect whether two conflicting accesses are unordered. When a race fires, it prints both stack traces. It has real overhead (roughly 2–10x CPU, 5–10x memory), so it is used in CI and development, not production.

**Example race:**
```go
var counter int
var wg sync.WaitGroup
for i := 0; i < 1000; i++ {
    wg.Add(1)
    go func() { defer wg.Done(); counter++ }()
}
wg.Wait()
// counter is almost never 1000
```

**Fix with `sync.Mutex`:**
```go
var mu sync.Mutex
var counter int
for i := 0; i < 1000; i++ {
    wg.Add(1)
    go func() {
        defer wg.Done()
        mu.Lock()
        counter++
        mu.Unlock()
    }()
}
```

**Fix with a channel** (share memory by communicating):
```go
inc := make(chan int)
done := make(chan int)
go func() {
    n := 0
    for d := range inc { n += d }
    done <- n
}()
for i := 0; i < 1000; i++ {
    wg.Add(1)
    go func() { defer wg.Done(); inc <- 1 }()
}
wg.Wait()
close(inc)
counter := <-done
```

Or simply use `sync/atomic.AddInt64`.

### G17 — Medium
**Answer:**
`select` lets a goroutine wait on **multiple channel operations** simultaneously. Each `case` must be a send or receive on a channel. It differs from `switch` in that `switch` branches on values, while `select` branches on **communication readiness**.

- If exactly one case is ready, it runs.
- If **multiple cases are ready simultaneously**, one is chosen **pseudo-randomly** (uniform) — this prevents starvation.
- If **no case is ready** and there is a `default`, the `default` runs immediately (non-blocking select).
- If no case is ready and there is no `default`, the goroutine blocks until one becomes ready.

A **timeout** is typically implemented with `time.After` (or, better, a `context`):

```go
select {
case msg := <-ch:
    fmt.Println("got", msg)
case <-time.After(2 * time.Second):
    fmt.Println("timeout")
}
```

Preferred in long-lived code:
```go
ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
defer cancel()
select {
case msg := <-ch:
    ...
case <-ctx.Done():
    return ctx.Err()
}
```
(`time.After` leaks a timer until it fires; `context.WithTimeout` + `cancel` does not.)

### G18 — Hard
**Answer:**
**Escape analysis** is a compile-time static analysis that decides, for every allocation, whether the value's lifetime can be proven to end before the function returns. If so, it is placed on the **stack** (cheap, freed on return, no GC pressure). If the value "escapes" — e.g., its address is returned, stored in a heap object, captured by a closure that outlives the function, or passed via an `interface{}`/channel in a way the compiler can't reason about — it is allocated on the **heap** and managed by the garbage collector.

Because Go has garbage collection, the language does not require you to decide; the compiler is free to promote stack allocations to the heap whenever it is uncertain. Taking the address of a local is **not** by itself enough to force a heap allocation — the compiler can keep it on the stack if the pointer doesn't escape.

**Inspecting decisions:**
```
go build -gcflags='-m' ./...        # prints "moved to heap", "does not escape", etc.
go build -gcflags='-m -m' ./...     # more detail, reasoning
```

**Why it matters:** heap allocations cost an allocation plus eventual GC marking/sweeping. In hot paths, unnecessary heap allocations inflate allocation rate, which drives GC CPU overhead and can double or triple latency. Writing allocation-free inner loops — reusing buffers, using `sync.Pool`, avoiding interface conversions, passing values instead of pointers when small — are common performance techniques, and escape analysis output is how you verify them.

### G19 — Hard
**Answer:**
The `reflect` package lets a program inspect and manipulate arbitrary Go values at runtime — the types, fields, methods, and values of things known only via `interface{}`.

- **`reflect.Type`** describes a type: its kind (`Int`, `Struct`, `Slice`, ...), name, fields, methods, etc. Obtained via `reflect.TypeOf(x)`.
- **`reflect.Value`** holds a concrete runtime value along with its type and lets you read/write it (when settable), call methods, index, iterate, etc. Obtained via `reflect.ValueOf(x)`.

They are distinct because you often want to reason about a type without having a value (e.g., walking a struct's fields), or about a value without knowing its static type. A `reflect.Value` has a `.Type()` method that returns its `reflect.Type`.

**Costs:**
- Every reflective operation does type checks, bounds checks, and often a heap allocation (boxing into `interface{}`/`reflect.Value`).
- Method/field lookup is by name string — no inlining, no devirtualization.
- Modifying a value requires it to be "addressable" (`reflect.ValueOf(&x).Elem()`), which adds indirection.
- Overall, reflection is routinely **10–100x** slower than equivalent direct code, with pressure on the allocator.

**When it's justified:**
- Generic serialization/deserialization (`encoding/json`, `encoding/gob`).
- ORMs / struct tag-driven mapping (`sqlx`, validators, config loaders).
- Test helpers (`reflect.DeepEqual`).
- Frameworks that must accept arbitrary user types once, at the edges.

**When to prefer code generation** (`go generate`, `stringer`, `protoc-gen-go`, `go/types`-based tools, or, since Go 1.18, **generics**): hot paths, tight loops, and anywhere you know the set of types at compile time. Generated code is type-safe, inlinable, and as fast as hand-written code.

### G20 — Hard
**Answer:**
`//go:embed` (Go 1.16+) is a compiler directive that embeds files from the module's source tree into the binary at compile time. It must appear immediately above a package-level `var` of type `string`, `[]byte`, or `embed.FS`, and the package must import `embed`.

```go
import "embed"

//go:embed banner.txt
var banner string              // or []byte

//go:embed assets/*.html assets/img/*
var assets embed.FS            // directory / glob

//go:embed all:static
var static embed.FS            // "all:" includes dotfiles/underscore files
```

- **Single file** → `string` or `[]byte` (whole contents).
- **Multiple files / directory / glob** → must be `embed.FS`. `embed.FS` is read-only and implements `io/fs.FS`, so it plugs into anything that takes an `fs.FS`:

```go
http.Handle("/", http.FileServer(http.FS(static)))
tmpl := template.Must(template.ParseFS(assets, "assets/*.html"))
sub, _ := fs.Sub(static, "static")   // re-root
```

**Limitations:**
- Paths are **relative to the Go source file** containing the directive and must stay inside the module — no `..`, no absolute paths, no symlinks outside the tree.
- Patterns use `path.Match` semantics (forward slashes, no `**`).
- By default, files/directories whose names start with `.` or `_` are **excluded**; prefix with `all:` to include them.
- Files are embedded with their original relative paths; directory entries in `embed.FS` always use forward slashes regardless of OS.
- The directive must be on the line **immediately above** the var — no blank line, no intervening comment.
- `embed.FS` is immutable; you cannot write to it.

---

## Section 2: Rust (R1–R20)

### R1 — Easy
**Answer:**
**Ownership** is Rust's compile-time discipline for managing memory (and other resources) without a garbage collector. Every value has exactly one "owner," and the compiler inserts the destructor (`Drop`) when the owner goes out of scope.

The three rules (from *The Rust Programming Language*):

1. **Each value in Rust has a single owner.**
2. **There can only be one owner at a time.** Assigning or passing a non-`Copy` value to another binding **moves** ownership; the original binding is no longer usable.
3. **When the owner goes out of scope, the value is dropped** (its `Drop::drop` runs, memory is freed).

These rules, combined with borrowing, eliminate use-after-free, double-free, and data races at compile time.

### R2 — Easy
**Answer:**
- **`String`** is an **owned, growable, heap-allocated** UTF-8 string. It owns its buffer (`Vec<u8>` under the hood) and can be mutated, resized, and moved.
- **`&str`** is a **borrowed string slice**: a fat pointer `(ptr, len)` into UTF-8 bytes that someone else owns. It is immutable and has a lifetime tied to the owner. String literals have type `&'static str`.

**In function signatures:**

- Accept **`&str`** when you only need to read: it's the most flexible — callers can pass `&String`, `&str`, a string literal, or any `Deref<Target = str>` type. This is the idiomatic choice for read-only APIs.
- Take **`String`** (by value) when the function needs to **own** the string — e.g., it will store it in a struct, send it across threads, or mutate it and return it.
- Take **`&mut String`** when you need to mutate an existing string in place (append, truncate).
- Return **`String`** when producing a new owned string; return **`&str`** only when you can borrow from an input (tie the lifetime explicitly).

```rust
fn greet(name: &str) -> String {       // read input, produce owned output
    format!("Hello, {name}!")
}
```

### R3 — Medium
**Answer:**
**Borrowing** lets you access a value without taking ownership, via references. The compiler's **borrow checker** enforces rules statically so references can never dangle and data races are impossible in safe code.

**Rules:**

1. At any given time, for a given value, you can have **either**:
   - **any number of shared (immutable) references** `&T`, **or**
   - **exactly one mutable reference** `&mut T`.
   (This is often summarized as "aliasing XOR mutability.")
2. **References must always be valid** — a reference's lifetime cannot outlive the value it points to. The compiler rejects code that would leave a dangling reference.
3. Rule 1 is enforced per non-overlapping lifetime, not per lexical scope: non-lexical lifetimes (NLL) end a borrow as soon as it is last used, so you can often create new borrows in the same scope afterward.
4. While any borrow exists, you cannot move the underlying value, and while a `&mut T` exists, no other access (read or write) to the value is allowed.

```rust
let mut v = vec![1, 2, 3];
let r1 = &v;
let r2 = &v;          // OK: multiple shared
println!("{r1:?} {r2:?}");
let m = &mut v;       // OK: r1/r2 no longer used (NLL)
m.push(4);
```

### R4 — Medium
**Answer:**
- **`Option<T>`** represents an optional value: `Some(T)` or `None`. Used where other languages return null.
- **`Result<T, E>`** represents a fallible computation: `Ok(T)` or `Err(E)`. `E` is any error type.

The **`?` operator** is shorthand for "propagate the error / None." On a `Result<T, E>` inside a function returning `Result<_, F>`, `expr?` either unwraps `Ok(v)` to `v` or early-returns `Err(e.into())` (converted via `From`). On `Option<T>`, it unwraps `Some(v)` or early-returns `None`. This replaces piles of `match` boilerplate.

```rust
use std::fs;
use std::io;
use std::path::Path;

fn read_file(path: &Path) -> io::Result<String> {
    let contents = fs::read_to_string(path)?; // io::Error propagates
    Ok(contents)
}
```

Or manually:
```rust
use std::fs::File;
use std::io::{self, Read};

fn read_file(path: &std::path::Path) -> io::Result<String> {
    let mut f = File::open(path)?;
    let mut s = String::new();
    f.read_to_string(&mut s)?;
    Ok(s)
}
```

### R5 — Medium
**Answer:**
All three are **smart pointers** that heap-allocate, but their ownership semantics differ:

- **`Box<T>`** — unique ownership on the heap. Like `unique_ptr<T>` in C++. Use it to:
  - store a value whose size isn't known at compile time (e.g., trait objects: `Box<dyn Trait>`);
  - break recursive types (`struct Node { next: Option<Box<Node>> }`);
  - move large values without copying them on the stack.
  Zero runtime cost beyond the allocation itself; derefs to `&T` / `&mut T`.

- **`Rc<T>`** — **reference-counted** shared ownership, **single-threaded** only. Multiple `Rc<T>` can point at the same allocation; the value is dropped when the count reaches zero. `Rc<T>` is `!Send`/`!Sync`, so it cannot cross threads. Uses non-atomic count operations, so it's cheap. For mutability, combine with `RefCell<T>` (`Rc<RefCell<T>>`).

- **`Arc<T>`** — **atomically** reference-counted shared ownership, **thread-safe**. Identical API to `Rc<T>` but uses atomic increments/decrements, making it `Send`/`Sync` when `T: Send + Sync`. Slightly more expensive than `Rc<T>` due to the atomics. For shared mutability across threads, combine with `Mutex<T>` or `RwLock<T>` (`Arc<Mutex<T>>`).

**Rule of thumb:** single owner → `Box`; many owners, one thread → `Rc`; many owners, many threads → `Arc`.

### R6 — Medium
**Answer:**
A **trait** defines a set of method signatures (and optional defaults, associated types, associated constants) that a type can implement. Any type can implement any trait — including traits and types from different crates, subject to the **orphan rule** (you must own either the trait or the type).

Similar to Go interfaces in spirit (abstract behavior, structural-ish), but:
- Trait implementations are **explicit** (`impl Trait for Type { ... }`), not inferred from method presence.
- Traits support **generics**, **associated types**, **default methods**, **supertraits**, and **operator overloading** (e.g., `Add`).
- Dispatch can be **static** (monomorphized, zero cost) or **dynamic** (vtable). Go interfaces are always dynamic.

**Generic with trait bound (`T: Trait`)** — **static dispatch, monomorphization**:
```rust
fn print_all<T: std::fmt::Debug>(items: &[T]) {
    for i in items { println!("{i:?}"); }
}
```
The compiler generates a specialized copy of `print_all` for each concrete `T`. Calls are direct, inlinable, zero cost. Produces larger binaries.

**Trait object (`dyn Trait`)** — **dynamic dispatch**:
```rust
fn print_all(items: &[&dyn std::fmt::Debug]) {
    for i in items { println!("{i:?}"); }
}
```
`&dyn Debug` is a fat pointer `(data_ptr, vtable_ptr)`. One function body handles all types, method calls go through the vtable (one indirect call, not inlinable). Smaller binary, runtime cost, and the trait must be **object-safe** (no generic methods, no `Self` by value in signatures, etc.). Use when you need **heterogeneous collections** (`Vec<Box<dyn Trait>>`) or want to avoid code bloat.

### R7 — Hard
**Answer:**
Rust's **lifetimes** are compile-time annotations that tie references to the scope of the data they borrow from. They let the borrow checker prove, across function boundaries, that no returned reference outlives its source. Lifetimes don't affect runtime — they're purely a static proof obligation.

The sample fails because the return type `&str` has an **elided lifetime** the compiler cannot unambiguously infer: the function has **two** input references (`x: &str`, `y: &str`) with independent (possibly different) lifetimes, and the return value may come from either. Lifetime elision rules only produce an output lifetime when there is exactly one input lifetime, or when `&self` is present. With two inputs, the compiler demands an explicit annotation.

**Fix** — tie inputs and output to a common lifetime `'a`:

```rust
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}
```

This says: "both inputs live at least for `'a`, and the returned reference is valid for `'a`." The caller picks `'a` to be the intersection of `x`'s and `y`'s lifetimes, and the borrow checker ensures the returned reference can't outlive either source.

### R8 — Hard
**Answer:**
`Send` and `Sync` are **auto (marker) traits** that describe thread-safety properties. They have no methods; the compiler auto-implements them for any type whose fields all implement them, and you can opt out with `impl !Send for T {}`.

- **`Send`**: a type is `Send` if it is safe to **transfer ownership** across threads. Almost all types are `Send`. Exceptions: `Rc<T>`, raw pointers, `MutexGuard<'_, T>`.
- **`Sync`**: a type `T` is `Sync` if `&T` is `Send` — i.e., it is safe for multiple threads to hold shared references to the same value concurrently. Equivalently, the type guarantees safe concurrent read access. `Cell<T>`, `RefCell<T>`, and `Rc<T>` are **not** `Sync`.

`thread::spawn` requires its closure to be `Send + 'static`, so any captured data must also be `Send`.

**Why `Rc<T>` can't cross threads:** `Rc<T>` updates its reference count with **ordinary (non-atomic) integer reads and writes**. If two threads cloned or dropped the same `Rc`, they'd race on the count — producing torn writes, lost decrements (memory leaks), or double-frees (use-after-free). Therefore `Rc<T>` is marked `!Send` and `!Sync`, and the compiler refuses to move it to another thread.

**Why `Arc<T>` is safe:** `Arc<T>` uses **atomic** reference-count operations (`fetch_add`/`fetch_sub` with appropriate memory orderings — `Relaxed` for increment, `Release`/`Acquire` for decrement and drop). This makes clone/drop race-free. `Arc<T>: Send + Sync` whenever `T: Send + Sync`. Note `Arc` only provides thread-safe **reference counting**, not thread-safe mutation — for shared mutation you still need `Arc<Mutex<T>>` or `Arc<RwLock<T>>`.

### R9 — Hard
**Answer:**
Rust's `async`/`await` is a **zero-cost, poll-based** coroutine model. An `async fn` or `async { ... }` block is compiled into a **state machine** implementing the `Future` trait:

```rust
pub trait Future {
    type Output;
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output>;
}
```

Each `.await` compiles to a suspension point: the compiler generates an `enum` with one variant per await point, storing the locals live across that point. Calling an `async fn` **does nothing** — it merely constructs this state machine. To make progress, something must repeatedly call `poll`.

An **executor** (e.g., Tokio, async-std, smol) owns a set of tasks, each task being a top-level future. When the executor polls a future:
- `Poll::Ready(val)` → task is done.
- `Poll::Pending` → the future has registered the current task's `Waker` (from `Context`) with some source of I/O or a timer. The executor parks the task until the waker is invoked; then it re-polls.

A **reactor** (often bundled with the executor, e.g., Tokio's `mio`-based reactor) uses OS facilities (`epoll`, `kqueue`, `io_uring`, IOCP) to wait on many file descriptors at once and wake the corresponding task's waker when I/O is ready. This lets a small number of OS threads drive millions of concurrent futures.

**Differences from Go's goroutines:**

| Aspect | Rust async | Go goroutines |
|---|---|---|
| Runtime | External crate (Tokio, ...); none in std | Built into the language runtime |
| Stacks | No per-task stack; state machine on heap (or inline) | Each goroutine has a growable stack (~2 KiB initial) |
| Scheduling | Cooperative; progress only on `.await` | Preemptive (since Go 1.14), GMP scheduler |
| Syntax | `async fn` / `.await`; colored functions | Plain function + `go` keyword; no coloring |
| Blocking | A blocking call inside async starves the executor; need `spawn_blocking` | Runtime can steal the P and spawn another M |
| Cost | Zero-cost when not awaited; generated state machines are tight | Cheap but not free; ~2 KiB minimum per goroutine |
| Cancellation | Drop the future | `context.Context` cooperation |

In short: Go's model is "many small preemptively-scheduled stacks managed by a built-in runtime"; Rust's is "compile futures into state machines, run them on a user-chosen cooperative executor, with zero runtime overhead when idle."

### R10 — Hard → Medium
**Answer:**
`unsafe` is a keyword that lets you perform operations whose safety the compiler cannot verify. It does **not** turn off the borrow checker or type system — it unlocks a small set of additional capabilities. You are asserting, as the programmer, that you have upheld the relevant invariants.

**Things you can do in an `unsafe` block (the "unsafe superpowers"):**

1. **Dereference a raw pointer** (`*const T`, `*mut T`).
2. **Call an `unsafe fn`** (including FFI — `extern "C"` functions from other languages).
3. **Access or modify a `static mut` variable.**
4. **Implement an `unsafe trait`** (e.g., `Send`, `Sync` manually).
5. **Access fields of a `union`.**

(Any three of the above satisfy the question.)

**When it's justified:**
- FFI / calling C libraries (`extern "C"`).
- Building safe abstractions over inherently unsafe primitives — e.g., `Vec`, `HashMap`, `Mutex`, concurrency primitives, lock-free data structures all use `unsafe` internally and expose a safe API.
- Performance-critical code where the safe idiom cannot express the optimization (e.g., `get_unchecked`, `MaybeUninit` to avoid double initialization).
- Low-level systems work: memory-mapped I/O, kernels, embedded peripherals.

The idiomatic rule is: keep `unsafe` blocks **small**, **well-commented** with a `// SAFETY: ...` justification for each invariant, and wrap them in a safe API that upholds those invariants. Never reach for `unsafe` just to silence the borrow checker.

### R11 — Easy
**Answer:**
**Pattern matching** lets you destructure and branch on the shape of a value. The main construct is `match`:

```rust
match value {
    Pattern1 => expr1,
    Pattern2 if guard => expr2,
    _ => default,
}
```

Patterns can match literals, ranges, tuples, structs, enum variants, references, slices, and can bind identifiers (`x @ 1..=5`).

`if let` is **syntactic sugar for a one-arm match** — it runs a block when a value matches a single pattern, and (optionally) an `else` otherwise. It's useful when you only care about one variant and don't want to write `_ => ()`:

```rust
if let Some(x) = maybe { println!("{x}"); }
// vs
match maybe {
    Some(x) => println!("{x}"),
    _ => (),
}
```

There's also `while let` for looping while a pattern matches, and `let ... else` for early-return on non-match.

**Exhaustiveness:** `match` **must cover every possible value** of the scrutinee. The compiler enforces this and errors with `non-exhaustive patterns` if you miss a case. This is how `match` on an `enum` statically prevents forgetting a variant — adding a new variant to an enum breaks every `match` in the codebase that doesn't use a wildcard, which is usually what you want. `if let`, by contrast, has **no exhaustiveness requirement** because the mismatched case is implicit.

### R12 — Easy
**Answer:**
- **`[T; N]`** is a **fixed-size array**: `N` is part of the type and known at compile time. It lives on the **stack** by default (unless boxed), its length is a compile-time constant, and it cannot grow or shrink.
- **`Vec<T>`** is a **growable, heap-allocated** vector: a struct `{ ptr, len, cap }` pointing at a heap buffer. Its length can change at runtime, and its capacity can exceed its current length.

**Growth on `push` beyond capacity:** when `len == cap` and you `push`, `Vec` **reallocates**: it asks the allocator for a new, larger buffer (typical strategy: double the capacity, with a minimum of 4 for the first growth), **memcpy**s the existing `len` elements into the new buffer (or moves them — for `Copy` types this is a bitwise copy; for non-`Copy` types the move is still a bitwise copy because moves in Rust are byte-for-byte), frees the old buffer, and updates `ptr`/`cap`. This doubling strategy gives amortized **O(1)** `push`. You can pre-allocate with `Vec::with_capacity(n)` or `reserve(additional)` to avoid intermediate reallocations.

### R13 — Easy
**Answer:**
Rust **`enum`s are tagged unions** (a.k.a. algebraic data types / sum types). Each variant is a distinct case, and variants can **carry data**:

```rust
enum Message {
    Quit,
    Move { x: i32, y: i32 },
    Write(String),
    ChangeColor(i32, i32, i32),
}
```

This is fundamentally richer than C `enum`s (which are just named integer constants) or Java `enum`s (a fixed set of singleton objects, though Java enums can have methods and per-variant data they are still nominally class instances). In Rust, an enum's memory layout is a discriminant plus a union of the variant payloads, and you use `match` to destructure them safely.

**`Option<T>`** is defined in the standard library as:
```rust
enum Option<T> {
    None,
    Some(T),
}
```

It replaces nullable pointers / nullable values: a value that "might not be there" is expressed as `Option<T>`, and you **cannot** use it without pattern-matching (or calling `unwrap`, `?`, etc.) to handle the `None` case. Because non-`Option` types can never be absent, there's no such thing as a "null reference" in safe Rust — this eliminates Tony Hoare's "billion-dollar mistake." Additionally, the compiler performs **niche optimization**: `Option<&T>`, `Option<Box<T>>`, and `Option<NonZeroU32>` are the same size as the inner type, because the null/zero bit pattern is reused as the `None` discriminant.

### R14 — Easy
**Answer:**
An `impl` block attaches **inherent methods** and **associated functions** to a type (or an implementation of a trait for a type):

```rust
struct Counter { n: u32 }

impl Counter {
    fn new() -> Self { Self { n: 0 } }      // associated function
    fn value(&self) -> u32 { self.n }       // &self
    fn inc(&mut self) { self.n += 1; }      // &mut self
    fn into_inner(self) -> u32 { self.n }   // self (consumes)
}
```

**Receiver types:**

- **`&self`** — immutable borrow. Read-only method; can be called any number of times, including concurrently (via shared references). Doesn't consume the value. Syntactic sugar for `self: &Self`.
- **`&mut self`** — unique mutable borrow. Lets the method modify `self`. While the call is active, nothing else can access the value. Sugar for `self: &mut Self`.
- **`self`** — takes the value **by ownership**, consuming it. The caller can no longer use the old binding after the call. Used for builder-style APIs and conversions (`.into_inner()`, `.into_iter()`).

**Associated functions** are functions defined on a type that **don't take `self`**. They're namespaced under the type and called with `Type::name(...)`. The canonical example is a constructor: `String::new()`, `Vec::with_capacity(16)`, `HashMap::new()`. They're the Rust equivalent of static methods, and by convention `new` is used for the idiomatic no-argument constructor.

### R15 — Easy
**Answer:**
The `#[derive(...)]` attribute is a **procedural macro** invocation that auto-generates a trait implementation for the annotated struct or enum. The compiler (or the providing crate) supplies the implementation based on the fields/variants.

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]
struct Point { x: i32, y: i32 }

// With serde:
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize)]
struct Config { name: String, port: u16 }
```

**Commonly derived traits** from `std`:
- **`Debug`** — `{:?}` formatting for diagnostics/logging.
- **`Clone`** — explicit deep `.clone()`.
- **`Copy`** — implicit bitwise copy on move (requires all fields `Copy`; also requires `Clone`).
- **`PartialEq`, `Eq`** — `==` / `!=`.
- **`PartialOrd`, `Ord`** — `<`, `>`, sorting.
- **`Hash`** — use in `HashMap`/`HashSet` keys.
- **`Default`** — `T::default()` zero-ish value.

From third-party crates: **`Serialize`**, **`Deserialize`** (serde); **`Error`** (thiserror); **`FromRow`** (sqlx); and many more via proc macros.

**You cannot derive a trait when:**
- Not every field implements that trait (e.g., can't derive `Copy` if any field is `String`; can't derive `Debug` if a field's type isn't `Debug`). The compiler's derive macro imposes a `where F: Trait` bound on every field type.
- The trait isn't `derive`-able at all — most user-defined traits aren't, unless their crate ships a proc macro for it. `std` traits that support derive: `Debug, Default, Clone, Copy, Hash, PartialEq, Eq, PartialOrd, Ord`.
- Semantic reasons: e.g., you want a custom `Debug` that hides secrets, or a `PartialEq` that ignores a cache field. In those cases, write `impl Trait for T` by hand.

### R16 — Medium
**Answer:**
`std::borrow::Cow<'a, B>` ("Clone-on-Write") is an enum with two variants:

```rust
pub enum Cow<'a, B: ?Sized + ToOwned + 'a> {
    Borrowed(&'a B),
    Owned(<B as ToOwned>::Owned),
}
```

It holds **either a borrowed reference** `&'a B` **or an owned value** `<B as ToOwned>::Owned` (e.g., `String` for `str`, `Vec<T>` for `[T]`, `PathBuf` for `Path`). It `Deref`s to `&B` so callers read it uniformly, and `to_mut(&mut self) -> &mut Owned` clones into the owned variant lazily when (and only when) you first need to mutate.

**Why it's useful:** it lets a function return or accept "data that is usually already in the right form, but might need to be transformed" without allocating in the common case.

**Canonical example — normalizing strings** (the one used by `std`):

```rust
use std::borrow::Cow;

fn normalize(input: &str) -> Cow<'_, str> {
    if input.chars().any(|c| c.is_ascii_uppercase()) {
        Cow::Owned(input.to_ascii_lowercase())  // allocate only when needed
    } else {
        Cow::Borrowed(input)                    // zero-copy fast path
    }
}

let a = normalize("hello");   // Borrowed, no allocation
let b = normalize("HELLO");   // Owned, one allocation
```

Compared to `fn normalize(input: &str) -> String` which **always** allocates (even for "hello"), `Cow` saves an allocation on every already-normalized input. Real-world users: `std::path::Path::to_string_lossy`, `percent_encoding`, `serde` borrowed-vs-owned deserialization, HTML/URL escaping libraries.

### R17 — Medium
**Answer:**
Rust's module system organizes code into a tree of **modules** within a crate. Keywords:

- **`mod foo;`** — **declares** a submodule named `foo`. The compiler looks for its contents in `foo.rs` or `foo/mod.rs` (relative to the current file). `mod foo { ... }` inlines the module.
- **`use path::to::Item;`** — **imports** an item into the current scope so you can refer to it by its short name instead of its full path. Purely a convenience; doesn't affect visibility.
- **`pub`** — **visibility modifier**. By default, items are private to their defining module. `pub` exposes them to the parent module (and outward). Variants: `pub(crate)`, `pub(super)`, `pub(in path)` for finer control.

**Filesystem mapping:**

- The crate root is `src/lib.rs` (library) or `src/main.rs` (binary).
- `mod foo;` in the crate root looks for either:
  - `src/foo.rs` (preferred, 2018+), or
  - `src/foo/mod.rs` (Rust 2015 style).
- A submodule inside `foo` (`mod bar;` inside `foo.rs`) looks for `src/foo/bar.rs`.
- Binaries in `src/bin/*.rs`, integration tests in `tests/*.rs`, examples in `examples/*.rs` each form their own crate roots.

**2015 → 2018 edition changes (module-system-relevant):**

- **`extern crate` is no longer required.** In 2015 you had to write `extern crate serde;` at the crate root to pull in a dependency; in 2018 they're implicit from `Cargo.toml`.
- **Paths in `use` are anchored differently.** In 2018, paths in `use` start with the crate name (`use my_crate::foo;` or `crate::foo;`, `super::foo;`, `self::foo;`), while in 2015 they were relative to the crate root by default. You can now say `use crate::foo::Bar;` unambiguously.
- **`foo.rs` + `foo/` is allowed** — you no longer need `foo/mod.rs`; you can put `foo.rs` alongside a `foo/` directory for its children.
- **Macros are imported via `use`** rather than `#[macro_use] extern crate`.

The 2018 rules are the ones you write in any new code today.

### R18 — Hard
**Answer:**
`Pin<P>` is a wrapper around a pointer type `P` (e.g., `Pin<&mut T>`, `Pin<Box<T>>`) that **guarantees the pointee will not be moved in memory** for the rest of its lifetime, unless `T: Unpin`. It's a **compile-time contract**: `Pin` doesn't pin anything at runtime; it statically prevents APIs from handing out `&mut T`, which is the only safe way to move a value out.

**Why it's needed — self-referential structs and `async`:**

Rust's `async fn` is compiled into a **state machine** (an anonymous struct implementing `Future`). Across each `.await`, the generator must save the locals that are live at that point. If one of those locals holds a reference to **another field of the same state machine**, the future becomes **self-referential**: moving the state machine in memory would invalidate the internal reference (dangling pointer). Because Rust otherwise lets you move any `T` freely via `mem::swap`, `Vec::push` reallocation, assignment, etc., such self-references would be unsound.

`Pin` solves this by making the `Future::poll` signature take `self: Pin<&mut Self>`. Once a future has been pinned (typically by being placed behind `Box::pin(...)` or pinned on the stack via `pin!`), the executor — and `poll` — can no longer move it. Self-references inside the state machine therefore stay valid across polls.

**`Unpin`** is an auto trait (implemented for nearly every type) that says "this type is **safe to move even when pinned**." For `T: Unpin`, `Pin<&mut T>` is effectively equivalent to `&mut T` — pinning is a no-op. Types that are **not** `Unpin` (like the anonymous futures generated by `async fn`, or `PhantomPinned` markers) are the ones that actually need the pinning guarantee. You can opt a type out of `Unpin` by including a `PhantomPinned` field; you can opt in with `impl Unpin for T {}` (safe, because it says "I promise I'm movable").

In short: `Pin` is the type-system tool that makes self-referential futures sound without a garbage collector or runtime move barrier; `Unpin` is the escape hatch for types that never needed the guarantee.

### R19 — Hard
**Answer:**
Rust has two families of macros, both of which run at **compile time** and expand into AST that is then type-checked.

**1. Declarative macros — `macro_rules!`**

Pattern-based rewriting. You define patterns of token trees and the tokens to substitute. Invoked with `name!(...)`.

```rust
macro_rules! vec_of {
    ($($x:expr),* $(,)?) => {{
        let mut v = Vec::new();
        $( v.push($x); )*
        v
    }};
}
let v = vec_of!(1, 2, 3);
```

Pros: simple, no extra crate, shipped in `std` (`println!`, `vec!`, `assert_eq!`). Cons: matching is limited to the `macro_rules!` DSL (fragment specifiers `expr`, `ident`, `ty`, `pat`, `tt`, ...), and complex logic is awkward.

**2. Procedural macros**

Arbitrary Rust code that runs at compile time, consuming a `TokenStream` and producing a `TokenStream`. Must live in a dedicated `proc-macro = true` crate. Three kinds:

- **Derive macros** — `#[derive(MyTrait)]` on a struct/enum. The macro receives the item's tokens and emits an `impl` block. Example: `#[derive(Serialize, Deserialize)]` from serde.
- **Attribute macros** — `#[my_attr(...)]` on an item. Rewrites the entire item (or replaces it). Example: `#[tokio::main]`, `#[rocket::get("/")]`.
- **Function-like macros** — `my_macro!(...)`, like `macro_rules!` but with arbitrary Rust logic. Example: `sqlx::query!`, `html! { ... }` from yew.

Procedural macros typically use the `syn` crate to parse input into an AST, `quote!` to build the output, and `proc-macro2` for tokens. They're more powerful than `macro_rules!` but slower to compile and require a separate crate.

**Hygiene rules**

Rust macros are **mostly hygienic**: identifiers introduced inside a macro expansion live in the **macro's own "syntax context,"** not the caller's. In practice:

- A `let x = ...;` inside a `macro_rules!` expansion does **not** shadow or collide with an `x` in the caller. The macro's `x` is a fresh binding.
- Conversely, identifiers **passed in** by the caller retain the caller's context and resolve normally.
- Paths inside `macro_rules!` resolve at the **definition site**, not the call site (so `$crate::foo` and absolute paths work reliably).

Declarative macros have **mixed-site hygiene**: local bindings are hygienic, but items/paths aren't strictly. Procedural macros have **no hygiene by default** — they emit raw tokens, though `quote!` paired with `Span::call_site()` / `Span::mixed_site()` lets authors choose the context explicitly. This is why well-written proc macros go out of their way to reference items via absolute paths (`::std::result::Result`) to avoid name clashes.

### R20 — Hard
**Answer:**
"**Zero-cost abstraction**" is Bjarne Stroustrup's slogan that Rust adopted wholesale: "What you don't use, you don't pay for. And what you do use, you couldn't hand-code any better." High-level constructs compile down to the same machine code you would have written by hand in C, with no runtime overhead for the abstraction itself.

**1. Iterators**

`Iterator` is a trait whose `next(&mut self) -> Option<Self::Item>` is a small, inlinable function. Adapter methods (`map`, `filter`, `fold`, `take`, `chain`, `zip`, ...) all return **new iterator types** that wrap the previous one. A chain like:

```rust
let sum: i64 = (0..1_000_000)
    .filter(|n| n % 2 == 0)
    .map(|n| n * n)
    .sum();
```

compiles into a single loop with no allocations and no closures boxed on the heap. Because every adapter is a concrete type and the closures are unique types, the optimizer **inlines everything** through `next()` and produces machine code indistinguishable from a hand-written `for` loop. LLVM frequently autovectorizes such chains.

**2. Generics + monomorphization**

Generic functions and types with trait bounds (`fn f<T: Trait>(x: T)`) are **monomorphized**: the compiler generates a **separate, fully specialized copy** of the function for each concrete `T` it is called with. Inside each copy, `T` is a concrete type, `Trait` method calls are **static calls** (not through a vtable), and the optimizer inlines and specializes aggressively. The cost is larger binaries and longer compile times; the runtime cost is **zero** compared to hand-writing a version per type.

**3. Static dispatch with trait bounds**

Calling `x.method()` on a value of type `T: Trait` compiles to a **direct call** to the monomorphized method, just like calling a concrete method. There is no vtable lookup, no indirect branch. This is why `impl Trait` arguments and `T: Trait` bounds are preferred over `dyn Trait` in hot paths — they get inlined. `dyn Trait` still exists for when you need runtime polymorphism, and it costs exactly one indirect call (same as a C function pointer).

**Together with other language features** — move semantics (no hidden copies or refcount traffic), stack-by-default (`Box` is explicit), no hidden allocations, RAII with `Drop`, no runtime, predictable `#[repr]` layouts — Rust routinely matches or beats C/C++ on benchmarks while offering lambdas, iterator chains, `Option`/`Result`, pattern matching, generic containers, and other high-level ergonomics. The abstractions are "paid for" at compile time, not runtime.
