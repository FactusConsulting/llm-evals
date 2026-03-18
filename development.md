# Development Knowledge Test Suite

**Purpose:** Evaluate model competency across Go, Rust, .NET (C#), Python, JavaScript/TypeScript, Bash, and PowerShell.
**Scoring:** Each question has a difficulty rating. Partial credit is fine — note what was correct vs. wrong/missing.

---

## Section 1: Go (20 questions)

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

### G11 — Easy
What is a pointer in Go? What is the zero value of a pointer? How do you create a pointer to a struct literal?

### G12 — Easy
Explain Go's `init()` function. When does it run? Can a package have multiple `init()` functions, and if so, in what order do they execute?

### G13 — Easy
What is the difference between `make` and `new` in Go? What types does each work with?

### G14 — Easy
How does error handling work in Go? What is the `error` interface, and what is the idiomatic pattern for checking errors? How do `errors.Is` and `errors.As` differ from `==`?

### G15 — Easy
What are Go's built-in composite types (map, slice, channel, struct)? What is the zero value of each?

### G16 — Medium
What is a race condition in Go? How does the `-race` flag work? Give an example of a data race and show how to fix it with `sync.Mutex` or a channel.

### G17 — Medium
Explain Go's `select` statement. How does it differ from a `switch`? What happens when multiple cases are ready? How do you implement a timeout with `select`?

### G18 — Hard
What is escape analysis in Go? How does the compiler decide whether to allocate on the stack or the heap? How can you inspect escape analysis decisions, and why does it matter for performance?

### G19 — Hard
Explain Go's reflection package (`reflect`). What is `reflect.Type` vs `reflect.Value`? What are the performance costs, and when is reflection justified vs code generation?

### G20 — Hard
What is the `go:embed` directive? How does it work for single files, directories, and file systems? What are the limitations, and how does it interact with `io/fs.FS`?

---

## Section 2: Rust (20 questions)

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

### R11 — Easy
What is pattern matching in Rust? How does `match` differ from `if let`? What does the compiler enforce about exhaustiveness?

### R12 — Easy
What is the difference between `Vec<T>` and an array `[T; N]`? How does `Vec` manage memory when elements are pushed beyond its current capacity?

### R13 — Easy
What are enums in Rust, and how do they differ from enums in C or Java? What is the `Option<T>` enum, and why does Rust not have null?

### R14 — Easy
Explain the `impl` block. What is the difference between methods that take `&self`, `&mut self`, and `self`? What are associated functions (e.g., `String::new()`)?

### R15 — Easy
What is the `derive` macro? Give examples of commonly derived traits (`Debug`, `Clone`, `PartialEq`, `Serialize`). When can you NOT derive a trait?

### R16 — Medium
What is `Cow<'a, T>` (clone on write)? When is it useful? Give an example where it avoids unnecessary allocations compared to always cloning.

### R17 — Medium
Explain Rust's module system. What is the difference between `mod`, `use`, and `pub`? How does the file system map to modules, and what changed between Rust 2015 and 2018 editions?

### R18 — Hard
What is the `Pin<T>` type and why is it needed? How does it relate to self-referential structs and `async`/`await`? What is `Unpin`?

### R19 — Hard
Explain Rust's macro system. What is the difference between declarative macros (`macro_rules!`) and procedural macros (derive, attribute, function-like)? What are hygiene rules?

### R20 — Hard
What are zero-cost abstractions in Rust? Explain how iterators, generics (monomorphization), and trait static dispatch achieve performance comparable to hand-written C while providing high-level ergonomics.

---

## Section 3: .NET / C# (20 questions)

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

### DN11 — Easy
What is the difference between `ref`, `out`, and `in` parameter modifiers in C#? When would you use each?

### DN12 — Easy
Explain nullable reference types in C# (the `?` annotation and `#nullable enable`). How do they differ from nullable value types (`int?`)?

### DN13 — Easy
What is LINQ? Explain the difference between method syntax (`list.Where(...)`) and query syntax (`from x in list where ...`). What is deferred execution?

### DN14 — Easy
What are generic constraints in C#? Explain `where T : class`, `where T : struct`, `where T : new()`, and `where T : IComparable<T>`. When would you combine multiple constraints?

### DN15 — Easy
What is the difference between `abstract class` and `interface` in C#? How did default interface methods (C# 8+) change this distinction?

### DN16 — Medium
Explain the middleware pipeline in ASP.NET Core. What is the difference between `app.Use()`, `app.Map()`, and `app.Run()`? How does ordering matter, and how does exception handling middleware work?

### DN17 — Medium
What is `Channel<T>` in .NET? How does it compare to `BlockingCollection<T>`? Give an example of using bounded channels for producer-consumer backpressure.

### DN18 — Hard
Explain Source Generators in .NET. How do they differ from reflection and IL weaving? What is an incremental generator, and why is it preferred over `ISourceGenerator`?

### DN19 — Hard
What is the `System.Threading.Tasks.Dataflow` library (TPL Dataflow)? Explain `ActionBlock`, `TransformBlock`, and `BufferBlock`. How does it compare to `System.Threading.Channels` for pipeline processing?

### DN20 — Hard
What are Minimal APIs in .NET? How do they differ from controller-based APIs? What are the trade-offs in terms of testability, middleware, and OpenAPI support? How do route groups and endpoint filters work?

---

## Section 4: Python (20 questions)

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

### P11 — Easy
What is a virtual environment, and why should you use one? What is the difference between `venv`, `virtualenv`, and `conda`?

### P12 — Easy
Explain list comprehensions, dict comprehensions, and set comprehensions. How do they relate to `map()` and `filter()`? When would you prefer one over the other?

### P13 — Easy
What is the difference between `==` and `is` in Python? What is object interning, and why does `a is b` sometimes return `True` for small integers?

### P14 — Easy
Explain Python's `*args` and `**kwargs`. How do positional-only (`/`) and keyword-only (`*`) parameter markers work in function signatures?

### P15 — Easy
What are context managers (`with` statement)? How do you write one using `__enter__`/`__exit__` vs `@contextmanager`? Give an example beyond file handling.

### P16 — Medium
What is type hinting in Python? Explain `typing.Union`, `Optional`, `Literal`, `TypeVar`, and `Protocol`. How does `mypy` or `pyright` use these for static analysis?

### P17 — Medium
Explain Python's data model (dunder methods). What are `__repr__` vs `__str__`, `__eq__` vs `__hash__`, and `__getattr__` vs `__getattribute__`? What happens if you define `__eq__` but not `__hash__`?

### P18 — Hard
What are descriptors in Python? Explain the descriptor protocol (`__get__`, `__set__`, `__delete__`). How do `property`, `classmethod`, and `staticmethod` use descriptors under the hood?

### P19 — Hard
Explain Python's import system in detail. What is the difference between relative and absolute imports? How does `sys.path`, `PYTHONPATH`, `__init__.py`, and namespace packages work? What is a finder and a loader?

### P20 — Hard
What is `dataclasses` and how does it compare to `attrs` and Pydantic? Explain `__post_init__`, field factories, frozen dataclasses, and how `dataclasses` interacts with inheritance. When would you choose Pydantic over dataclasses?

---

## Section 5: JavaScript / TypeScript (20 questions)

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

### JS11 — Easy
What is the difference between `null` and `undefined` in JavaScript? What does `==` vs `===` do when comparing them? What is nullish coalescing (`??`) and optional chaining (`?.`)?

### JS12 — Easy
Explain `map()`, `filter()`, and `reduce()` on arrays. How does `reduce()` work with an initial value? What is `flatMap()` and when is it useful?

### JS13 — Easy
What are template literals in JavaScript? How do tagged templates work? Give an example of a tagged template function (e.g., for HTML escaping or SQL queries).

### JS14 — Easy
What is destructuring in JavaScript? Explain object destructuring, array destructuring, default values, and renaming. How does the rest operator (`...`) work in destructuring?

### JS15 — Easy
What is the difference between `for...in` and `for...of`? What does each iterate over? Why should you avoid `for...in` on arrays?

### JS16 — Medium
Explain TypeScript generics. What are generic constraints (`extends`), conditional types (`T extends U ? X : Y`), and the `infer` keyword? Give a practical example of each.

### JS17 — Medium
What is the module system in JavaScript? Explain the differences between CommonJS (`require`/`module.exports`), ES Modules (`import`/`export`), and how Node.js handles both. What is the `"type": "module"` field in `package.json`?

### JS18 — Hard
Explain TypeScript's structural type system. What are excess property checks, and when do they apply? What is the difference between `extends` and `satisfies`? How does variance (`in`, `out`) work in TypeScript 4.7+?

### JS19 — Hard
What are `Proxy` and `Reflect` in JavaScript? How do you intercept property access, assignment, and function calls? Give a practical example (e.g., validation, logging, or reactive data binding).

### JS20 — Hard
Explain `SharedArrayBuffer` and `Atomics` in JavaScript. How do Web Workers communicate using shared memory? What are the ordering guarantees, and how does `Atomics.wait`/`Atomics.notify` work?

---

## Section 6: Bash (20 questions)

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

### B9 — Easy
What is the difference between single quotes (`'...'`), double quotes (`"..."`), and no quotes in bash? Give an example where each produces different output.

### B10 — Easy
How do you check if a file exists, is a directory, or is readable in bash? What is the difference between `[ ]` (test) and `[[ ]]`?

### B11 — Easy
What is the difference between `$?`, `$$`, `$!`, and `$#`? Give a use case for each.

### B12 — Easy
How do you define and use functions in bash? What is the difference between `function foo {}` and `foo() {}`? How do you return values from a function?

### B13 — Easy
What is the `PATH` environment variable? How does bash resolve commands? What is the difference between a builtin command and an external command? How do you check which one is being used?

### B14 — Medium
Explain `trap` in bash. How do you set up cleanup handlers for `EXIT`, `ERR`, `INT`, and `TERM`? What is the execution order when multiple signals arrive?

### B15 — Medium
What is the difference between `xargs` and command substitution? How do you handle filenames with spaces and newlines using `xargs -0` with `find -print0`? What is `xargs -P` for parallel execution?

### B16 — Medium
Explain bash arrays and associative arrays. How do you declare, append to, iterate over, and check the length of each? What are the differences in syntax and capabilities?

### B17 — Hard
What is the difference between a subshell (`(...)`) and a group command (`{ ...; }`)? How does each affect variable scope and exit codes? Why does piping into a `while` loop lose variable changes?

### B18 — Hard
Explain how bash handles signals and job control. What is the difference between `SIGINT`, `SIGTERM`, `SIGHUP`, and `SIGKILL`? How do you make a script handle graceful shutdown with background processes?

### B19 — Hard
Write a bash script that processes a large log file in parallel using `split`, `xargs -P`, and a processing function — then merges the results. Explain the performance trade-offs and how to handle error propagation from parallel jobs.

### B20 — Hard
What is the difference between `exec` and running a command normally? How do you use `exec` for file descriptor manipulation (e.g., `exec 3>file`, `exec 3>&-`)? Explain how to implement a bash coprocess and when you would use one.

---

## Section 7: PowerShell (20 questions)

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

### PS9 — Easy
What is the difference between `@()` and `[array]` in PowerShell? How do you force a single result into an array? What happens when you index into `$null` vs an empty array?

### PS10 — Easy
Explain PowerShell's comparison operators (`-eq`, `-ne`, `-like`, `-match`, `-contains`, `-in`). How do they differ from their case-sensitive variants (`-ceq`, `-clike`, etc.)? What is the difference between `-contains` and `-in`?

### PS11 — Easy
What is a PowerShell module? What is the difference between a script module (`.psm1`), a manifest module (`.psd1`), and a binary module? How does `Import-Module` work?

### PS12 — Easy
How does string interpolation work in PowerShell? What is the difference between `"..."` and `'...'`? How do you include expressions in interpolated strings? What is a here-string (`@"..."@`)?

### PS13 — Easy
What is `Get-Member`? How do you explore objects in the pipeline? What is the difference between `Properties`, `Methods`, and `NoteProperties`? How does `Select-Object` differ from `Where-Object`?

### PS14 — Medium
What are PowerShell classes (introduced in v5)? How do they differ from C# classes? What are the limitations around inheritance, interfaces, and constructors? When would you use a class vs a function?

### PS15 — Medium
Explain PowerShell's `CmdletBinding` and advanced functions. What does `[CmdletBinding()]` enable? What are `SupportsShouldProcess`, `DefaultParameterSetName`, and `ValueFromPipeline`? How do `Begin`, `Process`, and `End` blocks work?

### PS16 — Medium
What is the PowerShell providers system? Explain how `Get-ChildItem` works across different providers (FileSystem, Registry, Certificate, Environment). How do you access the registry like a file system?

### PS17 — Hard
Explain PowerShell's runspaces and thread safety. What is a `[runspace]`, `[runspacepool]`, and `[powershell]` object? How do you use `ForEach-Object -Parallel` (v7+) vs manual runspace management for parallel execution?

### PS18 — Hard
What is `PSScriptAnalyzer`? How does it enforce coding standards? Explain the difference between rules, severity levels, and custom rules. How do you suppress rules, and how does it integrate with CI/CD pipelines?

### PS19 — Hard
What is the difference between `$using:` scope and `$args`/`-ArgumentList` when passing variables to remote sessions, background jobs, and `ForEach-Object -Parallel`? What are the serialization limits (CLIXML depth), and how do they affect complex objects?

### PS20 — Hard
Explain Desired State Configuration (DSC). What are configurations, resources, and the Local Configuration Manager (LCM)? How does DSC differ between Windows PowerShell and PowerShell 7+? What replaced it in modern infrastructure-as-code?

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
| Go            | 20        | 40        |
| Rust          | 20        | 40        |
| .NET / C#     | 20        | 40        |
| Python        | 20        | 40        |
| JavaScript/TS | 20        | 40        |
| Bash          | 20        | 40        |
| PowerShell    | 20        | 40        |
| **Total**     | **140**   | **280**   |
