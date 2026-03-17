# Development Knowledge Test Suite

**Purpose:** Evaluate model competency across Go, Rust, .NET (C#), Python, JavaScript/TypeScript, Bash, and PowerShell.
**Scoring:** Each question has a difficulty rating. Partial credit is fine — note what was correct vs. wrong/missing.

---

## Section 1: Go (10 questions)

### G1 — Easy
What is the difference between a slice and an array in Go? What happens when you append to a slice that has reached its capacity?

### G2 — Easy
Explain the difference between `var x int` and `x := 0`. When can you NOT use `:=`?

### G3 — Medium
What is a goroutine, and how does it differ from an OS thread? What is the role of the Go scheduler (GMP model)?

### G4 — Medium
Explain how channels work in Go. What is the difference between a buffered and unbuffered channel? What happens when you send to a full buffered channel?

### G5 — Medium
What is the `context` package used for? Write a minimal example of using `context.WithTimeout` to cancel a long-running HTTP request.

### G6 — Medium
Explain Go's interface satisfaction model. How does it differ from Java/C# interfaces? What is the empty interface `interface{}` (or `any`) and why is it both powerful and dangerous?

### G7 — Hard
Explain Go's memory model regarding goroutine visibility. Why is the following unsafe, and what are the correct alternatives?
```go
var ready bool
var data string

go func() {
    data = "hello"
    ready = true
}()

for !ready {}
fmt.Println(data)
```

### G8 — Hard
What is the difference between `sync.Mutex` and `sync.RWMutex`? When would you use `sync.Map` vs a regular map with a mutex? What are the performance trade-offs?

### G9 — Hard
Explain how Go modules work. What is the difference between `go.mod` and `go.sum`? What does `go mod tidy` do, and what is the Minimum Version Selection (MVS) algorithm?

### G10 — Medium
What is a `defer` statement? In what order do multiple defers execute? What is a common gotcha with `defer` in a loop?

---

## Section 2: Rust (10 questions)

### R1 — Easy
What is ownership in Rust? Explain the three ownership rules.

### R2 — Easy
What is the difference between `String` and `&str`? When would you use each in function signatures?

### R3 — Medium
Explain borrowing and the borrow checker. What are the rules for shared (`&T`) and mutable (`&mut T`) references?

### R4 — Medium
What is a `Result<T, E>` and an `Option<T>`? How does the `?` operator work? Write a function that reads a file and returns its contents or an error.

### R5 — Medium
Explain the difference between `Box<T>`, `Rc<T>`, and `Arc<T>`. When would you use each?

### R6 — Medium
What are traits in Rust? How do they compare to Go interfaces? What is a trait object (`dyn Trait`) vs a generic with a trait bound (`T: Trait`)?

### R7 — Hard
Explain lifetimes in Rust. Why does the following fail to compile, and how do you fix it?
```rust
fn longest(x: &str, y: &str) -> &str {
    if x.len() > y.len() { x } else { y }
}
```

### R8 — Hard
What is `Send` and `Sync` in Rust? Why can't you send an `Rc<T>` across threads? What makes `Arc<T>` safe for concurrent use?

### R9 — Hard
Explain how Rust's `async`/`await` works under the hood. What is a `Future`? What is the role of the executor (e.g., Tokio)? How does this differ from Go's goroutines?

### R10 — Medium
What is `unsafe` in Rust? Give 3 things you can do in an `unsafe` block that you can't do in safe Rust. When is `unsafe` justified?

---

## Section 3: .NET / C# (10 questions)

### DN1 — Easy
What is the difference between `class` and `struct` in C#? When should you use a struct?

### DN2 — Easy
Explain the difference between `IEnumerable<T>` and `IQueryable<T>`. Why does this distinction matter for database queries?

### DN3 — Medium
How does `async`/`await` work in C#? What is a `Task` vs a `ValueTask`? When should you use `ValueTask`?

### DN4 — Medium
Explain dependency injection in .NET. What are the three service lifetimes (`Transient`, `Scoped`, `Singleton`), and what is a common bug when injecting a `Scoped` service into a `Singleton`?

### DN5 — Medium
What is the difference between `string` and `ReadOnlySpan<char>` for string processing? When would you use `Span<T>` and why?

### DN6 — Medium
Explain how the .NET garbage collector works. What are generations (Gen 0, 1, 2)? What is the Large Object Heap? What is `IDisposable` and why do you need it if you have a GC?

### DN7 — Hard
What is the difference between `ConfigureAwait(false)` and the default behavior? When should you use it, and when should you NOT? How does this relate to `SynchronizationContext`?

### DN8 — Hard
Explain the new .NET 8/9 features: primary constructors, collection expressions, and `FrozenDictionary`. Write a minimal example using primary constructors with DI.

### DN9 — Hard
You have a .NET API that works fine under low load but throws `ObjectDisposedException` on the `DbContext` under high concurrency. Diagnose the likely cause and explain the fix. How does EF Core's `DbContext` lifetime interact with DI scoping?

### DN10 — Medium
What is the difference between `record` and `class` in C#? What about `record struct`? When would you choose each?

---

## Section 4: Python (10 questions)

### P1 — Easy
What is the difference between a list and a tuple? What about a `set` vs a `frozenset`?

### P2 — Easy
Explain the GIL (Global Interpreter Lock). What types of workloads does it affect, and what are the workarounds?

### P3 — Medium
What is the difference between `deepcopy` and `copy`? Give an example where shallow copy causes unexpected behavior.

### P4 — Medium
Explain Python decorators. Write a decorator that logs the execution time of any function.

### P5 — Medium
What are generators and `yield`? How do they differ from returning a list? What is `yield from`?

### P6 — Medium
Explain Python's `asyncio` event loop. What is the difference between `asyncio.run()`, `asyncio.gather()`, and `asyncio.create_task()`? Why can't you call `time.sleep()` inside an async function?

### P7 — Hard
Explain Python's MRO (Method Resolution Order). What algorithm does Python 3 use? What happens with diamond inheritance, and why does the following print what it does?
```python
class A:
    def who(self): return "A"
class B(A):
    pass
class C(A):
    def who(self): return "C"
class D(B, C):
    pass
print(D().who())
```

### P8 — Hard
What is a metaclass? When would you use `__init_subclass__` vs a metaclass? Give a practical use case for each.

### P9 — Hard
Explain the difference between `multiprocessing`, `threading`, and `concurrent.futures` in Python. When would you use each? What are the serialization implications of `multiprocessing` (pickling)?

### P10 — Medium
What is `__slots__`? When should you use it, and what does it prevent? What is the memory impact?

---

## Section 5: JavaScript / TypeScript (10 questions)

### JS1 — Easy
Explain the difference between `var`, `let`, and `const`. What is hoisting?

### JS2 — Easy
What is the event loop? Explain the relationship between the call stack, microtask queue, and macrotask queue.

### JS3 — Medium
What is a closure? Give a practical example. What is the classic `for` loop closure bug, and how do you fix it?

### JS4 — Medium
Explain `Promise`, `async`/`await`, and how error handling works with both. What is `Promise.allSettled` vs `Promise.all`?

### JS5 — Medium
What is the difference between TypeScript's `interface` and `type`? When would you use each? What are discriminated unions?

### JS6 — Medium
Explain prototypal inheritance in JavaScript. How does `Object.create()` work? How do ES6 classes relate to prototypes?

### JS7 — Hard
Explain the `this` keyword in JavaScript. What are the 4 binding rules (in priority order)? What does `bind()` return, and can you re-bind it?

### JS8 — Hard
What is `WeakRef` and `FinalizationRegistry`? When would you use them? Explain why `WeakMap` keys must be objects and how this relates to garbage collection.

### JS9 — Hard
Explain how the V8 engine optimizes JavaScript. Cover: hidden classes, inline caching, and deoptimization. What coding patterns cause deoptimization?

### JS10 — Medium
What is tree-shaking? How does it work with ES modules vs CommonJS? Why can't CommonJS be tree-shaken effectively?

---

## Section 6: Bash (8 questions)

### B1 — Easy
What is the difference between `$@` and `$*`? What about `"$@"` vs `"$*"`?

### B2 — Easy
What does `set -euo pipefail` do? Explain each flag.

### B3 — Medium
What is the difference between `$(command)` and `` `command` ``? What about `$((expression))` vs `expr`?

### B4 — Medium
Explain process substitution (`<(command)`) and when you would use it. Give a practical example with `diff`.

### B5 — Medium
How do you safely iterate over files with spaces or special characters in their names? Why is `for f in $(ls)` dangerous?

### B6 — Medium
What is a here document (`<<EOF`) vs a here string (`<<<`)? What does `<<-EOF` do differently?

### B7 — Hard
Explain the difference between these redirections:
```bash
cmd > file 2>&1
cmd 2>&1 > file
cmd &> file
```
Why do the first two produce different results?

### B8 — Hard
Write a bash function that safely creates a lock file with proper cleanup, handles race conditions, and works correctly if the script is killed with SIGTERM. Explain why `mkdir` is preferred over file creation for locking.

---

## Section 7: PowerShell (8 questions)

### PS1 — Easy
What is the difference between `Write-Output` and `Write-Host`? Why does this distinction matter in pipelines?

### PS2 — Easy
Explain the PowerShell pipeline. What is the difference between `ForEach-Object` and `foreach` statement? When is each appropriate?

### PS3 — Medium
What is the difference between `[PSCustomObject]` and `[hashtable]`? When would you use each? How do you convert between them?

### PS4 — Medium
Explain PowerShell's error handling. What is the difference between terminating and non-terminating errors? How do `-ErrorAction`, `$ErrorActionPreference`, and `try/catch` interact?

### PS5 — Medium
What is splatting (`@params`)? Give an example. How does it differ from passing a hashtable as a single parameter?

### PS6 — Medium
Explain PowerShell remoting. What is the difference between `Invoke-Command -ComputerName` and `Enter-PSSession`? What protocol does it use, and how does it relate to WinRM and SSH?

### PS7 — Hard
Explain PowerShell's type system and the pipeline's implicit behavior. Why does this produce unexpected results?
```powershell
function Get-Items {
    $result = @()
    $result += "one"
    return $result
}
$x = Get-Items
$x.GetType().Name  # What is this?
```
What about when the function returns 0 items? What is the correct pattern?

### PS8 — Hard
What is the difference between `[scriptblock]` and a function? How do you pass a scriptblock to a remote session? What is the double-hop problem, and how do you solve it with `CredSSP` or `Invoke-Command -ArgumentList`?

---

## Scoring Guide

| Rating  | Criteria                                                                 |
|---------|--------------------------------------------------------------------------|
| ✅ Pass  | Correct, complete, and demonstrates understanding                        |
| ⚠️ Partial | Mostly correct but missing key details or contains a minor error        |
| ❌ Fail  | Incorrect, significantly incomplete, or demonstrates misunderstanding    |

**Per section:** Count ✅=2, ⚠️=1, ❌=0 → max score per section is 2× question count.

| Section       | Questions | Max Score |
|---------------|-----------|-----------|
| Go            | 10        | 20        |
| Rust          | 10        | 20        |
| .NET / C#     | 10        | 20        |
| Python        | 10        | 20        |
| JavaScript/TS | 10        | 20        |
| Bash          | 8         | 16        |
| PowerShell    | 8         | 16        |
| **Total**     | **66**    | **132**   |
