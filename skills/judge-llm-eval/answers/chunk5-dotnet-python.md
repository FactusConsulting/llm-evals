# .NET + Python Knowledge Test Suite — Answers

---

## Section 1: .NET / C# (DN1–DN20)

### DN1 — Easy
**Answer:**
`class` is a reference type (allocated on the heap, passed by reference, nullable, has identity). `struct` is a value type (allocated inline/on the stack when local, copied by value, non-nullable by default, cannot inherit from other structs/classes but can implement interfaces).

Use a `struct` when:
- The type is small (typically ≤16 bytes).
- It represents a single logical value (coordinates, measurements, identifiers).
- It is immutable.
- It has short lifetime / high allocation churn you want to avoid.
- You want value semantics (e.g. `Point`, `DateTime`, `Guid`).

Avoid structs for large types, mutable data, or types you frequently box. When in doubt, use a `class`.

```csharp
public readonly struct Point(double X, double Y)
{
    public double Distance(Point other)
        => Math.Sqrt(Math.Pow(X - other.X, 2) + Math.Pow(Y - other.Y, 2));
}
```

---

### DN2 — Easy
**Answer:**
- `IEnumerable<T>` represents an in-memory sequence. LINQ operators compile to delegates (`Func<...>`) executed client-side; every `Where`/`Select` iterates the source in .NET.
- `IQueryable<T>` represents a query expression tree. LINQ operators build an `Expression<Func<...>>` that a provider (e.g. EF Core) translates into SQL and executes server-side.

Why it matters for DB queries: if you cast an EF `DbSet<T>` to `IEnumerable<T>` too early (e.g. `.AsEnumerable()` before `.Where`), filtering happens in memory after pulling the entire table. Keep it as `IQueryable<T>` so predicates translate to SQL `WHERE` clauses.

```csharp
// BAD: pulls every user, filters in memory
var users = db.Users.AsEnumerable().Where(u => u.IsActive).ToList();

// GOOD: translates to SELECT ... WHERE IsActive = 1
var users = await db.Users.Where(u => u.IsActive).ToListAsync();
```

---

### DN3 — Medium
**Answer:**
`async`/`await` is compiler sugar over a state machine. `async` methods return a `Task`/`Task<T>`/`ValueTask<T>` and yield control at each `await` point: the compiler rewrites the method into a state machine that captures locals, hooks a continuation onto the awaited task, and returns to the caller. When the awaited operation completes, the continuation resumes (on the captured `SynchronizationContext`/`TaskScheduler` unless `ConfigureAwait(false)`).

- `Task`/`Task<T>`: reference type, cached singletons for trivial completions, always allocates for new work. General-purpose.
- `ValueTask<T>`: struct wrapper over either a synchronously-available result or an `IValueTaskSource<T>`. Avoids heap allocation on hot paths where the method usually completes synchronously (e.g. buffered `Stream.ReadAsync`).

Use `ValueTask<T>` when:
- The method is called on a very hot path.
- It frequently completes synchronously.
- You can guarantee the result is awaited exactly once and not stored/awaited twice.

Otherwise prefer `Task<T>` — it is simpler, cacheable, and composable with `Task.WhenAll`, etc.

```csharp
public async ValueTask<int> ReadAsync(Memory<byte> buf, CancellationToken ct)
{
    if (_buffered.Length > 0) return CopyFromBuffer(buf); // sync path, no alloc
    return await _stream.ReadAsync(buf, ct);
}
```

---

### DN4 — Medium
**Answer:**
Dependency Injection in .NET is built around `IServiceCollection` (registration) and `IServiceProvider` (resolution). You register services in `Program.cs`/`Startup.cs` and the framework constructor-injects them into controllers, middleware, hosted services, etc.

Lifetimes:
- **Transient**: a new instance every time it is requested. Use for lightweight, stateless services.
- **Scoped**: one instance per DI scope. In ASP.NET Core, one per HTTP request. Use for `DbContext`, per-request state.
- **Singleton**: one instance for the whole application lifetime. Use for caches, config, thread-safe stateless helpers.

Common bug — **captive dependency**: injecting a Scoped (or Transient) service into a Singleton. The singleton captures the first scoped instance it ever sees and keeps using it for the entire app lifetime, even after that scope is disposed. This causes `ObjectDisposedException` on the captured `DbContext`, stale data, and thread-safety violations.

Fix: inject `IServiceScopeFactory` (or `IServiceProvider`) into the singleton and create a new scope per unit of work:

```csharp
public sealed class Worker(IServiceScopeFactory scopes) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            using var scope = scopes.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await DoWorkAsync(db, ct);
        }
    }
}
```

`ValidateScopes = true` (default in Development) catches captive dependencies at startup.

---

### DN5 — Medium
**Answer:**
- `string` is an immutable, heap-allocated, UTF-16 reference type. Every `Substring`, `Trim`, `Split` allocates a new string.
- `ReadOnlySpan<char>` is a stack-only `ref struct` that points into an existing buffer (string, `char[]`, stackalloc) with no allocation. Slicing is a pointer+length adjustment.

Use `Span<T>`/`ReadOnlySpan<T>` for:
- Zero-allocation parsing (`int.Parse(ReadOnlySpan<char>)`, `Utf8Parser`).
- Hot-path string slicing where GC pressure matters.
- Interop with `stackalloc` buffers or native memory.

Constraints: `Span<T>` cannot be stored on the heap, in async state machines, in iterators, as a field of a normal class, or captured by lambdas. For those cases use `Memory<T>`/`ReadOnlyMemory<T>`.

```csharp
static int SumCsv(ReadOnlySpan<char> input)
{
    int total = 0;
    foreach (var range in input.Split(','))
        total += int.Parse(input[range]);
    return total;
}
```

---

### DN6 — Medium
**Answer:**
The .NET GC is a **generational, tracing, compacting** garbage collector. It groups objects by age:

- **Gen 0**: newly allocated small objects. Collected most frequently, very cheap.
- **Gen 1**: survivors of one Gen 0 collection. Acts as a buffer between short- and long-lived objects.
- **Gen 2**: long-lived objects. Full collection — most expensive.
- **Large Object Heap (LOH)**: objects ≥85,000 bytes. Allocated directly in Gen 2, historically not compacted (compaction is opt-in via `GCSettings.LargeObjectHeapCompactionMode`). Causes fragmentation if churned.
- **POH (Pinned Object Heap)**: .NET 5+, for long-lived pinned buffers.

The GC marks roots (stack, statics, GC handles), traces reachable objects, sweeps the rest, and compacts survivors (except historically LOH).

**`IDisposable`** exists because the GC only manages *managed memory*. Unmanaged resources — file handles, sockets, DB connections, native memory, OS handles — are not tracked by the GC and must be released deterministically. `IDisposable.Dispose()` (usually via `using`) releases them immediately. Finalizers (`~Foo()`) are a safety net but non-deterministic and expensive. The canonical pattern:

```csharp
public sealed class Resource : IDisposable
{
    private SafeFileHandle? _handle;
    public void Dispose()
    {
        _handle?.Dispose();
        _handle = null;
    }
}
```

---

### DN7 — Hard
**Answer:**
`await task` by default captures the current `SynchronizationContext` (or `TaskScheduler.Current` if none) and posts the continuation back to it. `ConfigureAwait(false)` tells the awaiter: "don't bother, resume on any thread-pool thread."

`SynchronizationContext` is the abstraction that lets WinForms/WPF/older ASP.NET marshal continuations back to the UI thread / request thread.

**Use `ConfigureAwait(false)`:**
- In **library code** where you don't know the caller's context. Avoids forcing callers onto a single context and prevents UI deadlocks when the caller blocks with `.Result` / `.Wait()`.
- In any code path that doesn't touch UI controls or request-bound state.

**Don't use it:**
- In **UI event handlers** that need to update controls after `await` (WinForms/WPF/MAUI) — you need the UI context back.
- In **ASP.NET Core** app code (controllers, middleware) — there is no `SynchronizationContext`, so `ConfigureAwait(false)` is a no-op. It's neither harmful nor helpful in app code; most teams skip it in ASP.NET Core and keep it only in shared libraries.

The classic deadlock: UI thread calls `someTask.Result`, the task's continuation tries to post back to the (blocked) UI thread → deadlock. `ConfigureAwait(false)` inside the library breaks the cycle.

```csharp
// Library code
public async Task<string> FetchAsync(Uri uri)
{
    using var resp = await _http.GetAsync(uri).ConfigureAwait(false);
    return await resp.Content.ReadAsStringAsync().ConfigureAwait(false);
}
```

---

### DN8 — Hard
**Answer:**
- **Primary constructors (C# 12)**: parameters declared on the type header are in scope for the entire type body, replacing boilerplate field init. Works on `class`, `struct`, `record`.
- **Collection expressions (C# 12)**: `[1, 2, 3]` target-typed literal that works with arrays, `List<T>`, `Span<T>`, `ImmutableArray<T>`, any type with a `[CollectionBuilder]` attribute. Supports spreads: `[..a, ..b, 42]`.
- **FrozenDictionary / FrozenSet (.NET 8)**: immutable, read-optimized collections in `System.Collections.Frozen`. Built once via `ToFrozenDictionary()`, then lookups are significantly faster than `Dictionary<TKey,TValue>`. Use for config/lookup tables computed at startup.

Minimal primary constructor + DI example:

```csharp
using Microsoft.Extensions.Logging;

public sealed class OrderService(
    IOrderRepository repo,
    ILogger<OrderService> logger)
{
    public async Task<Order> PlaceAsync(OrderRequest req, CancellationToken ct)
    {
        logger.LogInformation("Placing order for {Customer}", req.CustomerId);
        var order = new Order(req.CustomerId, [.. req.Items]); // collection expr
        await repo.SaveAsync(order, ct);
        return order;
    }
}

// Program.cs
builder.Services.AddScoped<IOrderRepository, SqlOrderRepository>();
builder.Services.AddScoped<OrderService>();
```

---

### DN9 — Hard
**Answer:**
Symptoms — `ObjectDisposedException: Cannot access a disposed object. Object name: 'AppDbContext'` under concurrent load.

**Most likely cause**: a captive / shared `DbContext`. `DbContext` is **not thread-safe** and is registered as **Scoped** (one per HTTP request) by `AddDbContext`. Common ways the bug manifests:

1. A singleton service (cache, background hosted service, static) captures the `DbContext` from the first request and reuses it after that scope is disposed.
2. Controller code does `Task.WhenAll(db.X.ToListAsync(), db.Y.ToListAsync())` — two concurrent operations on the *same* context. Under load the second call can hit a disposed connection / race the first.
3. Fire-and-forget `Task.Run(() => db.SaveChangesAsync())` after the request has ended → the scope is already gone.
4. Storing `DbContext` in a static field or an `IMemoryCache` entry.

**Fix**: obey scoping. For background work, inject `IDbContextFactory<T>` (registered with `AddDbContextFactory`) or `IServiceScopeFactory` and create a fresh context per operation:

```csharp
// Startup
builder.Services.AddDbContextFactory<AppDbContext>(o =>
    o.UseNpgsql(cfg.GetConnectionString("Db")));

// Background worker
public sealed class Importer(IDbContextFactory<AppDbContext> factory) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await using var db = await factory.CreateDbContextAsync(ct);
        await db.Imports.AddAsync(new Import(), ct);
        await db.SaveChangesAsync(ct);
    }
}
```

Never await two `DbContext` operations in parallel on the same instance; sequence them or use separate contexts. Enable `ServiceProviderOptions.ValidateScopes = true` to catch captive deps at startup.

---

### DN10 — Medium
**Answer:**
- **`class`**: reference type, reference equality by default, mutable, no built-in value semantics.
- **`record` (class)** (C# 9): reference type with compiler-generated value-based `Equals`/`GetHashCode`, `ToString`, `Deconstruct`, and a `with` expression for non-destructive mutation. Primary constructor defines init-only positional properties.
- **`record struct`** (C# 10): value type + the same record niceties (value equality, `with`, etc). Mutable by default; add `readonly` to make immutable.
- **`struct`**: value type, default equality is field-wise but via reflection (slow) unless you override it.

Choose:
- `class` — most OO services, entities with identity, things with behavior and mutable state.
- `record` — immutable DTOs, value-like reference types (events, messages, API contracts).
- `record struct` — small immutable values where you also want equality/`with` without heap allocation (e.g. `Money`, `Coordinate`).
- `struct` — small values where you manage equality manually or use `record struct`.

```csharp
public record Person(string First, string Last);
public readonly record struct Money(decimal Amount, string Currency);
```

---

### DN11 — Easy
**Answer:**
All three pass by reference, but with different initialization/assignment rules:

- **`ref`**: variable must be assigned before the call; the callee can read and write it.
- **`out`**: variable need not be assigned before the call; the callee *must* assign it before returning. Used for multiple return values (e.g. `int.TryParse(s, out int n)`).
- **`in`**: pass by readonly reference. Callee can read but not modify. Used to avoid copying large structs while preserving immutability.

```csharp
void Swap(ref int a, ref int b) { (a, b) = (b, a); }
bool TryGet(string key, out string value) { value = "hi"; return true; }
double Length(in Vector3 v) => Math.Sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z);
```

---

### DN12 — Easy
**Answer:**
**Nullable reference types (NRT)** — enabled with `#nullable enable` or `<Nullable>enable</Nullable>` in the csproj — turn the `?` suffix on reference types into a compile-time *annotation*. The compiler performs flow analysis and warns when you dereference a possibly-null value or assign `null` to a non-nullable reference. **At runtime, a `string?` is still just a `string`** — the type is identical; only the metadata and warnings change.

**Nullable value types** (`int?`, i.e. `Nullable<int>`) are a completely different feature: a real struct wrapper (`Nullable<T>`) with a `HasValue` flag and `Value` payload. It changes the runtime type and boxing behavior.

```csharp
#nullable enable
string?  maybeName = null;   // compile-time annotation only
int?     maybeAge  = null;   // actual Nullable<int> struct

if (maybeName is not null) Console.WriteLine(maybeName.Length); // no warning
```

---

### DN13 — Easy
**Answer:**
**LINQ** (Language-Integrated Query) is a set of standard query operators (`Where`, `Select`, `GroupBy`, `Join`, `OrderBy`, …) that work on `IEnumerable<T>` and `IQueryable<T>`, plus C# language syntax for expressing queries.

- **Method syntax**: fluent calls — `list.Where(x => x > 3).Select(x => x * x)`.
- **Query syntax**: SQL-like keywords — `from x in list where x > 3 select x * x`. The compiler rewrites it into method-syntax calls, so they are equivalent. Query syntax is often clearer for multi-`from`/`join`/`group`.

**Deferred execution**: LINQ operators that return `IEnumerable<T>`/`IQueryable<T>` do *not* execute when you call them; they build a pipeline that runs only when enumerated (`foreach`, `ToList`, `ToArray`, `First`, `Count`, etc.). This lets you compose queries cheaply and means the source is re-evaluated each time you enumerate.

```csharp
var q = numbers.Where(n => { Console.WriteLine(n); return n > 2; });
// nothing printed yet
foreach (var _ in q) { }     // prints now
foreach (var _ in q) { }     // prints AGAIN
```

---

### DN14 — Easy
**Answer:**
Generic constraints restrict what a type parameter `T` can be, enabling operations on it in the generic code.

- `where T : class` — `T` must be a reference type (nullable reference if `T : class?`).
- `where T : struct` — `T` must be a non-nullable value type.
- `where T : new()` — `T` must have a public parameterless constructor (lets you do `new T()`).
- `where T : IComparable<T>` — `T` must implement `IComparable<T>` (lets you call `a.CompareTo(b)`).

Other useful ones: `where T : SomeBaseClass`, `where T : unmanaged`, `where T : notnull`, `where T : U` (another type parameter).

Combine them when you need multiple capabilities — class constraint first, then interfaces, then `new()` last:

```csharp
public T CreateSorted<T>() where T : class, IComparable<T>, new()
{
    var t = new T();
    // ... use CompareTo, treat as reference type ...
    return t;
}
```

---

### DN15 — Easy
**Answer:**
- **`abstract class`**: can have state (fields), constructors, mix of abstract and concrete members, access modifiers on members, and a class can only inherit one. Models an "is-a" relationship with shared implementation.
- **`interface`**: historically pure contract — no fields/state, no constructors, all members public, a class can implement many. Models a capability ("can do").

**C# 8 default interface methods (DIMs)** let an interface provide a default implementation for a method, so you can add new members to an existing interface without breaking implementers. That blurred the line, but differences remain:

- Interfaces still cannot hold instance fields/state. (Static fields and static abstracts from C# 11 are allowed.)
- Interfaces still support multiple inheritance; abstract classes do not.
- Default interface members are resolved differently (they aren't virtual via the class's vtable by default; you call them through the interface).

Rule of thumb: use an abstract class when you need shared state/implementation; use an interface to define a capability or to enable multiple inheritance of behavior.

---

### DN16 — Medium
**Answer:**
ASP.NET Core processes each request through a **middleware pipeline** — an ordered chain of delegates where each can inspect/modify the request, call `next`, then inspect/modify the response. It's built in `Program.cs` via `WebApplication`/`IApplicationBuilder`.

- `app.Use(async (ctx, next) => { /* before */ await next(); /* after */ })` — adds middleware that can call (or short-circuit) the next component.
- `app.Map("/admin", adminApp => { ... })` — branches the pipeline based on the request path prefix.
- `app.Run(async ctx => { ... })` — terminal middleware that does not call `next`; ends the pipeline.

**Ordering matters** — middleware runs top-to-bottom on the request side and bottom-to-top on the response side. The canonical order is: ExceptionHandler → HSTS → HttpsRedirection → StaticFiles → Routing → CORS → Authentication → Authorization → EndpointMiddleware. Putting `UseAuthorization` before `UseAuthentication`, or routing after endpoints, breaks things.

**Exception handling** middleware (`app.UseExceptionHandler("/error")` or `app.UseDeveloperExceptionPage()`) must be registered *first* so it wraps everything downstream. When a later middleware throws, control unwinds to the exception handler, which re-executes the pipeline for the error path (or produces a ProblemDetails response).

```csharp
var app = builder.Build();

app.UseExceptionHandler("/error");
app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.Run();
```

---

### DN17 — Medium
**Answer:**
`System.Threading.Channels.Channel<T>` is a high-performance, **async-friendly**, lock-free producer/consumer queue. A `Channel<T>` exposes a `ChannelWriter<T>` and `ChannelReader<T>`; readers/writers `await` on empty/full state instead of blocking.

Comparison to `BlockingCollection<T>`:

| | `Channel<T>` | `BlockingCollection<T>` |
|---|---|---|
| API | Async (`WriteAsync`, `ReadAsync`, `WaitToReadAsync`) | Blocking (`Take`, `Add`) |
| Backpressure | Bounded channels `await` when full | Blocks thread when full |
| Allocation | Low, optimized for async | Higher, thread-blocking |
| Use case | Modern async pipelines | Legacy thread-based producer/consumer |

Prefer `Channel<T>` in new async code; `BlockingCollection<T>` when you're stuck with synchronous thread-per-worker code.

Bounded channel with backpressure:

```csharp
var channel = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(100)
{
    FullMode = BoundedChannelFullMode.Wait,
    SingleReader = false,
    SingleWriter = false,
});

// Producer
_ = Task.Run(async () =>
{
    foreach (var item in Source())
        await channel.Writer.WriteAsync(item); // awaits when queue full
    channel.Writer.Complete();
});

// Consumer
await foreach (var item in channel.Reader.ReadAllAsync())
    await ProcessAsync(item);
```

---

### DN18 — Hard
**Answer:**
**Source Generators** are Roslyn components that run during compilation, inspect the compilation's syntax trees and semantic model, and *emit additional C# source files* that are compiled alongside your code. Output is plain C#; nothing is injected post-compile.

- **vs. reflection**: reflection is runtime, pays a startup and per-call cost, can't be trimmed or AOT-compiled well, and can't be statically verified. Source generators do the work at build time → zero runtime reflection cost, trim/AOT friendly, easy to debug as real code.
- **vs. IL weaving** (Fody, PostSharp): IL weaving mutates already-compiled IL, which is harder to debug, can break analyzers/tooling, and is not Roslyn-native. Source generators only *add* code and integrate with incremental builds, IDE, and NuGet cleanly.

**`ISourceGenerator`** (original API) runs every time anything in the compilation changes — bad for IDE performance on large solutions.

**`IIncrementalGenerator`** (the preferred API since .NET 6/C# 10) models the generator as a pipeline of `IncrementalValueProvider<T>` transforms. Roslyn caches the output of each stage keyed on input equality, so unchanged inputs short-circuit. The result is vastly better IDE responsiveness and incremental build times. It's now the only recommended shape; `ISourceGenerator` is effectively legacy.

Examples in the wild: `System.Text.Json` source generator, `LoggerMessage` generator, `Regex` generator, `GeneratedComInterface`.

---

### DN19 — Hard
**Answer:**
**TPL Dataflow** (`System.Threading.Tasks.Dataflow`) is a library of composable blocks for in-process message-passing pipelines. Each block has an input buffer, optional processing, and an output buffer; you `LinkTo` blocks to form a graph.

Key blocks:
- **`ActionBlock<T>`**: terminal. Accepts items and runs an `Action`/`Func<T, Task>` on each. Supports `MaxDegreeOfParallelism`, `BoundedCapacity`, async delegates.
- **`TransformBlock<TIn, TOut>`**: accepts `TIn`, produces `TOut`. Core of a pipeline stage.
- **`TransformManyBlock<TIn, TOut>`**: produces zero-or-many outputs per input (fan-out).
- **`BufferBlock<T>`**: pure FIFO queue with no processing. Useful as a fan-in/fan-out point or decoupling buffer.
- **`BroadcastBlock<T>`**: keeps only the latest item, broadcasts to all linked targets.
- **`BatchBlock<T>`**: groups N items into `T[]`.

Comparison to `System.Threading.Channels`:

| | TPL Dataflow | Channels |
|---|---|---|
| Abstraction | High-level pipeline graph | Low-level async queue |
| Parallelism | Built-in (`MaxDegreeOfParallelism`) | You write the loop |
| Backpressure | `BoundedCapacity` | `CreateBounded` |
| Overhead | Heavier, more allocations | Very light |
| Async-first | Partial (delegates can be async) | Fully async |
| Use case | Complex ETL-style graphs, fan-in/out | Simple high-throughput async producer/consumer |

Channels are usually the better choice for new code unless you specifically need Dataflow's graph wiring and built-in parallelism knobs.

```csharp
var download = new TransformBlock<string, byte[]>(
    async url => await http.GetByteArrayAsync(url),
    new ExecutionDataflowBlockOptions { MaxDegreeOfParallelism = 4, BoundedCapacity = 16 });

var save = new ActionBlock<byte[]>(
    bytes => File.WriteAllBytesAsync(Path.GetTempFileName(), bytes),
    new ExecutionDataflowBlockOptions { BoundedCapacity = 16 });

download.LinkTo(save, new DataflowLinkOptions { PropagateCompletion = true });
```

---

### DN20 — Hard
**Answer:**
**Minimal APIs** (.NET 6+) are a lightweight way to build HTTP endpoints without MVC controllers. You register routes directly on `WebApplication`:

```csharp
var app = builder.Build();
app.MapGet("/users/{id:int}", async (int id, AppDb db) => await db.Users.FindAsync(id) is {} u ? Results.Ok(u) : Results.NotFound());
app.Run();
```

Differences from controllers:
- No `Controller` base class, no action filters, no model binding attributes (though most attributes like `[FromBody]`, `[FromServices]` still work).
- Binding is inferred from parameter type (route/query/services/body).
- Less ceremony; great for microservices and small APIs.

**Trade-offs:**
- *Testability*: controller actions are just methods, easy to unit-test in isolation; minimal APIs tied to lambdas are harder to unit-test directly (people extract handlers into named methods or classes, use `WebApplicationFactory` integration tests).
- *Middleware*: identical — minimal APIs run in the same ASP.NET Core pipeline.
- *OpenAPI*: supported via `Microsoft.AspNetCore.OpenApi`/Swashbuckle + `.WithOpenApi()`, `.Produces<T>()`, `.WithName()`, etc. Controllers get richer metadata for free via attributes; minimal APIs need more explicit calls but parity has improved a lot in .NET 7/8/9.
- *Features like model validation, filters, versioning*: historically controller territory; endpoint filters and route groups close most of the gap.

**Route groups** (`MapGroup`) let you share a path prefix, filters, metadata, and auth across a set of endpoints:

```csharp
var users = app.MapGroup("/users").RequireAuthorization().WithTags("Users");
users.MapGet("/{id:int}", GetUser);
users.MapPost("/", CreateUser);
```

**Endpoint filters** (`AddEndpointFilter`) are the minimal-API analogue of action filters. They run per-endpoint around the handler and can short-circuit or transform the result:

```csharp
app.MapPost("/orders", CreateOrder)
   .AddEndpointFilter(async (ctx, next) =>
   {
       if (ctx.HttpContext.User.Identity?.IsAuthenticated != true)
           return Results.Unauthorized();
       return await next(ctx);
   });
```

Use minimal APIs for small/microservices and internal tools; use controllers when you need the full MVC feature set (complex model validation, OData, conventions) or a larger team already standardized on them.

---

## Section 2: Python (P1–P20)

### P1 — Easy
**Answer:**
- **`list`**: mutable, ordered sequence. Supports append/insert/remove. `[1, 2, 3]`.
- **`tuple`**: immutable, ordered sequence. Hashable if all elements are hashable, so can be used as dict keys / set members. Slightly less memory and faster to iterate. `(1, 2, 3)`.
- **`set`**: mutable, unordered collection of unique hashable elements. Supports O(1) membership and set algebra (`|`, `&`, `-`, `^`). `{1, 2, 3}`.
- **`frozenset`**: immutable, hashable version of `set`. Can be used as dict key / set member. `frozenset({1, 2, 3})`.

Rule of thumb: use a `tuple` for fixed records / hashable composites, a `list` for mutable sequences, a `set` for dedup/membership, and a `frozenset` when you need a set you can hash.

---

### P2 — Easy
**Answer:**
The **GIL** is a mutex in CPython that ensures only one thread executes Python bytecode at a time. It exists to make reference counting and C-extension state simple and safe.

- **CPU-bound pure-Python workloads** are serialized — adding threads gives no speedup, sometimes a slowdown.
- **I/O-bound workloads** (network, disk, subprocess) are *not* hurt because the GIL is released around blocking I/O calls and around long-running C code (numpy, zlib, hashlib, ...). Threads are fine here.

Workarounds:
- **`multiprocessing`** / `concurrent.futures.ProcessPoolExecutor`: separate processes, each with its own interpreter and GIL. True parallelism, but IPC costs (pickling).
- **C extensions** that release the GIL (numpy, pandas, PyTorch, polars, numba).
- **`asyncio`** for I/O concurrency without threads.
- **PEP 703 / free-threaded CPython** (3.13+ experimental, 3.14 GA target): optional `--disable-gil` build.
- **Subinterpreters per PEP 684** (3.12+): each interpreter has its own GIL.

---

### P3 — Medium
**Answer:**
- `copy.copy(x)` — **shallow copy**. Creates a new outer container but copies *references* to the inner objects.
- `copy.deepcopy(x)` — **deep copy**. Recursively copies every nested object, handling cycles via a memo dict.

Shallow copy bites when you mutate a nested mutable:

```python
import copy

original = [[1, 2], [3, 4]]
shallow  = copy.copy(original)
shallow[0].append(99)

print(original)   # [[1, 2, 99], [3, 4]]  <-- also mutated!
print(shallow)    # [[1, 2, 99], [3, 4]]

deep = copy.deepcopy(original)
deep[0].append(42)
print(original)   # unchanged
```

Use `deepcopy` when you need true isolation; note it is slow and can break on objects with non-picklable state unless they implement `__deepcopy__`.

---

### P4 — Medium
**Answer:**
A **decorator** is a callable that takes a function and returns a (usually wrapped) function. Python's `@decorator` syntax is sugar for `f = decorator(f)`. Use `functools.wraps` to preserve the wrapped function's `__name__`, `__doc__`, and signature.

```python
import functools
import logging
import time
from typing import Callable, ParamSpec, TypeVar

P = ParamSpec("P")
R = TypeVar("R")
log = logging.getLogger(__name__)

def timed(func: Callable[P, R]) -> Callable[P, R]:
    @functools.wraps(func)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        start = time.perf_counter()
        try:
            return func(*args, **kwargs)
        finally:
            elapsed = time.perf_counter() - start
            log.info("%s took %.3f ms", func.__qualname__, elapsed * 1000)
    return wrapper

@timed
def slow_add(a: int, b: int) -> int:
    time.sleep(0.1)
    return a + b
```

---

### P5 — Medium
**Answer:**
A **generator** is a function containing `yield`. Calling it returns a generator object — an iterator that runs the body lazily, pausing at each `yield` and resuming on the next `next()`/`for` step.

Differences from returning a list:
- **Memory**: only one item materialized at a time — can iterate infinite or huge streams.
- **Laziness**: work is done on demand, enabling pipelines and early termination.
- **Single-pass**: generators are exhausted after one iteration; lists can be iterated repeatedly.
- **Indexing/length**: generators don't support `len()` or random access.

`yield from iterable` delegates iteration (and `.send()`/`.throw()`/`.return`) to a sub-iterator. It's shorthand for `for x in iterable: yield x`, but also forwards values and exceptions properly — essential for composing generators.

```python
def flatten(nested):
    for item in nested:
        if isinstance(item, list):
            yield from flatten(item)
        else:
            yield item

list(flatten([1, [2, [3, 4], 5], 6]))  # [1, 2, 3, 4, 5, 6]
```

---

### P6 — Medium
**Answer:**
`asyncio` runs coroutines on a single-threaded **event loop** that multiplexes I/O via `selectors`. When a coroutine `await`s a future, the loop suspends it and resumes another ready task.

- **`asyncio.run(coro)`** — top-level entry point. Creates a new event loop, runs the coroutine to completion, closes the loop. Call it *once* from synchronous code.
- **`asyncio.create_task(coro)`** — schedules a coroutine to run concurrently on the current loop and returns a `Task`. The task starts executing at the next await point. Must be awaited (or the result retrieved) — orphan tasks are a common bug; keep a strong reference.
- **`asyncio.gather(*aws)`** — schedules multiple awaitables concurrently and awaits them all, returning their results as a list (or raising the first exception, unless `return_exceptions=True`). In 3.11+, `asyncio.TaskGroup` is the preferred structured-concurrency alternative.

`time.sleep(n)` **blocks the OS thread** — since the event loop *is* that thread, every other task is frozen for `n` seconds. Use `await asyncio.sleep(n)` instead, which yields to the loop. Same rule applies to any blocking call (`requests.get`, DB drivers without async support) — wrap them in `asyncio.to_thread(fn, ...)` or use an async-native library.

```python
import asyncio

async def fetch(name, delay):
    await asyncio.sleep(delay)
    return name

async def main():
    results = await asyncio.gather(fetch("a", 1), fetch("b", 2))
    print(results)

asyncio.run(main())
```

---

### P7 — Hard
**Answer:**
Python's **Method Resolution Order** determines the order in which base classes are searched for an attribute. Python 3 uses the **C3 linearization** algorithm, which guarantees:

1. Subclasses appear before their bases.
2. The order of bases in the class definition is preserved.
3. Monotonicity — a parent's MRO is preserved in children.

You can inspect it via `Cls.__mro__` or `Cls.mro()`.

For the example:

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

`D.__mro__` is `(D, B, C, A, object)`. Attribute lookup for `who` walks this list:
1. `D` — not defined.
2. `B` — not defined.
3. `C` — defined → returns `"C"`.

So it prints `C`. Even though `B` is listed first, `B` doesn't define `who`, and C3 ensures `C` is searched before the common ancestor `A`, so `C.who` wins over `A.who`.

---

### P8 — Hard
**Answer:**
A **metaclass** is the class of a class. `type` is the default metaclass; `class Foo(metaclass=Meta): ...` makes `Meta` responsible for *constructing* `Foo` itself. Metaclasses hook `__new__`/`__init__`/`__call__` at class-creation time and can rewrite the class body, register subclasses, enforce invariants, etc.

**`__init_subclass__`** (PEP 487, 3.6+) is a classmethod on the *parent* class that Python calls each time a new subclass is defined. It covers ~80% of the historical use cases for metaclasses without the complexity (and without the single-metaclass-per-hierarchy restriction).

**Use `__init_subclass__` when** you only need to react to subclass creation — registering plugins, validating required attributes, injecting defaults:

```python
class Plugin:
    registry: dict[str, type["Plugin"]] = {}

    def __init_subclass__(cls, *, name: str, **kwargs):
        super().__init_subclass__(**kwargs)
        Plugin.registry[name] = cls

class JsonPlugin(Plugin, name="json"):
    ...
```

**Use a metaclass when** you need to change *how* the class itself is constructed, intercept instance creation, control `isinstance`/`issubclass`, or manipulate the namespace at build time. Practical examples: Django/SQLAlchemy ORM models (turning class-level `Field` descriptors into table metadata), ABCs (`abc.ABCMeta`), Enum (`enum.EnumMeta`).

```python
class SingletonMeta(type):
    _instances: dict[type, object] = {}
    def __call__(cls, *a, **kw):
        if cls not in cls._instances:
            cls._instances[cls] = super().__call__(*a, **kw)
        return cls._instances[cls]

class Config(metaclass=SingletonMeta):
    ...
```

Reach for `__init_subclass__` first; drop to metaclasses only when it isn't enough.

---

### P9 — Hard
**Answer:**
- **`threading`**: multiple OS threads in one process, sharing memory. Constrained by the GIL for CPU-bound Python code but great for I/O-bound work (sockets, subprocess, blocking DB calls). Cheap to start, easy shared state, but needs locks to be correct.
- **`multiprocessing`**: separate OS processes, each with its own Python interpreter and GIL. True CPU parallelism. Communication via pipes/queues/`Manager`/shared memory. Startup and IPC are expensive; all data crossing the boundary must be **pickled** (on `spawn`/`forkserver`) which rules out lambdas, local functions, unpicklable objects (open files, sockets, DB connections). On Linux, `fork` avoids pickling but inherits global state and can cause subtle bugs (e.g. with OpenMP, CUDA).
- **`concurrent.futures`**: high-level executor API (`ThreadPoolExecutor`, `ProcessPoolExecutor`) on top of the above. Gives you `submit`/`map`/`Future` and hides pool/lifecycle details. Prefer it for most new code.

Rule of thumb:
- I/O-bound → `ThreadPoolExecutor` or `asyncio`.
- CPU-bound pure Python → `ProcessPoolExecutor` / `multiprocessing`.
- CPU-bound with native extensions that release the GIL (numpy/torch) → threads work fine.

```python
from concurrent.futures import ProcessPoolExecutor

def heavy(n):  # CPU-bound
    return sum(i*i for i in range(n))

if __name__ == "__main__":
    with ProcessPoolExecutor() as ex:
        for r in ex.map(heavy, [10_000_000] * 8):
            print(r)
```

Pickling implications: worker functions and their arguments must be importable from a module (define them at module top level, not inside `if __name__ == "__main__"` on `spawn`), and lambdas/closures can't be sent across the boundary. Large argument payloads become IPC cost, so prefer shared memory (`multiprocessing.shared_memory`, `numpy` memmap) for bulk data.

---

### P10 — Medium
**Answer:**
`__slots__` is a class attribute (tuple/list of names) that tells Python to store instances' attributes in a fixed-size array instead of a per-instance `__dict__`.

```python
class Point:
    __slots__ = ("x", "y")
    def __init__(self, x: float, y: float):
        self.x = x
        self.y = y
```

Effects:
- **Prevents** adding attributes not listed in `__slots__` (`AttributeError`).
- **Removes** per-instance `__dict__` and `__weakref__` (unless you include them).
- **Memory**: significant savings — often 40–60% less per instance — because you no longer pay for a dict per object. Relevant when creating millions of small objects.
- Slightly **faster** attribute access (direct slot descriptors instead of dict lookup).

Caveats:
- Inheritance: all classes in the hierarchy must define `__slots__` to retain the benefit; otherwise a `__dict__` reappears.
- Multiple inheritance with slots is restricted (only one non-empty `__slots__` base unless layouts match).
- Breaks code that monkey-patches instance attributes.
- Dataclasses get slot support via `@dataclass(slots=True)` (3.10+).

Use `__slots__` for small, numerous, fixed-shape value objects; skip it for general-purpose classes where flexibility matters.

---

### P11 — Easy
**Answer:**
A **virtual environment** is an isolated Python installation — its own `site-packages`, interpreter symlink, and activation script — so project dependencies don't collide with system packages or other projects. Reproducibility, reliability, and avoiding "works on my machine" issues.

- **`venv`**: standard-library module (`python -m venv .venv`). Lightweight, ships with Python 3.3+. The default recommendation.
- **`virtualenv`**: third-party predecessor to `venv`. Still maintained; supports older Pythons and is slightly faster to create environments. Functionally similar for most modern uses.
- **`conda`** (Anaconda/Miniconda/Mamba): full environment manager that also handles non-Python binaries (CUDA, MKL, R, C libs) via its own package repository. Useful for data-science stacks with native deps; heavier than `venv`.

Modern tools (`uv`, `poetry`, `hatch`, `pdm`, `pipenv`) build on top of `venv` and add lockfile/dependency management.

```bash
python -m venv .venv
source .venv/bin/activate   # .venv\Scripts\activate on Windows
pip install -r requirements.txt
```

---

### P12 — Easy
**Answer:**
Comprehensions build a collection by iterating an iterable with optional filtering and transformation, in a single expression.

```python
squares      = [x*x for x in range(10)]                 # list
even_squares = [x*x for x in range(10) if x % 2 == 0]   # list + filter
lookup       = {w: len(w) for w in words}               # dict
uniques      = {x % 5 for x in nums}                    # set
gen          = (x*x for x in range(10))                 # generator expr
```

Relation to `map`/`filter`:
- `[f(x) for x in xs]` ≡ `list(map(f, xs))`
- `[x for x in xs if p(x)]` ≡ `list(filter(p, xs))`
- `[f(x) for x in xs if p(x)]` ≡ `list(map(f, filter(p, xs)))`

**Prefer comprehensions** in idiomatic Python: they're more readable, support destructuring, multiple sources, `if`/`else` in the expression, and dict/set outputs directly. Use `map`/`filter` when you already have a named function and want to avoid the `lambda`, or when passing to another functional API. Use a **generator expression** when the result is only iterated once and you want to avoid materializing a list.

---

### P13 — Easy
**Answer:**
- **`==`** calls `__eq__` — compares *values*.
- **`is`** compares *identity* — whether two names point to the exact same object in memory (`id(a) == id(b)`).

Use `is` only for singletons like `None`, `True`, `False` (`x is None`). Use `==` for value comparisons.

**Interning**: CPython caches certain immutable objects so that equal literals share one object. Small integers in the range `[-5, 256]` are pre-allocated at interpreter startup, and most short identifier-like strings are automatically interned. That's why:

```python
a = 200
b = 200
a is b        # True  (cached small int)

a = 1000
b = 1000
a is b        # usually False (not cached)  — may be True inside a single expression
              # due to compiler constant folding, which is an implementation detail
```

This is a CPython optimization and **not a language guarantee** — never rely on it. Always use `==` for equality.

---

### P14 — Easy
**Answer:**
- **`*args`** collects extra *positional* arguments into a tuple.
- **`**kwargs`** collects extra *keyword* arguments into a dict.

In a call site, `*` and `**` **unpack** an iterable/dict into positional/keyword arguments.

- **`/`** (PEP 570, 3.8+) marks parameters before it as **positional-only** — they cannot be passed by name.
- **`*`** (bare) marks parameters after it as **keyword-only** — they must be passed by name.

```python
def connect(host, port, /, *, timeout=5.0, **options):
    ...

connect("db", 5432, timeout=2.0, sslmode="require")   # ok
connect(host="db", port=5432)                         # TypeError: positional-only
connect("db", 5432, 2.0)                              # TypeError: keyword-only
```

Positional-only keeps you free to rename parameters later; keyword-only forces self-documenting call sites and prevents accidental ordering bugs.

---

### P15 — Easy
**Answer:**
A **context manager** is an object implementing `__enter__` and `__exit__`, used with the `with` statement for deterministic setup/teardown (acquire-release, transactions, timers, mocking).

```python
with open("f.txt") as f:
    data = f.read()
# f is closed here, even on exception
```

Two ways to write one:

**Class-based:**

```python
class Timer:
    def __enter__(self):
        self.start = time.perf_counter()
        return self
    def __exit__(self, exc_type, exc, tb):
        self.elapsed = time.perf_counter() - self.start
        return False  # don't suppress exceptions
```

**`@contextmanager` decorator** from `contextlib` — uses a generator split around a single `yield`:

```python
from contextlib import contextmanager

@contextmanager
def temporary_env(key: str, value: str):
    import os
    old = os.environ.get(key)
    os.environ[key] = value
    try:
        yield
    finally:
        if old is None:
            del os.environ[key]
        else:
            os.environ[key] = old

with temporary_env("DEBUG", "1"):
    run_tests()
```

Other practical examples: DB transactions (`with conn.begin():`), locks (`with lock:`), `unittest.mock.patch`, `tempfile.TemporaryDirectory`, `decimal.localcontext`.

For async, use `__aenter__`/`__aexit__` + `async with`, or `@contextlib.asynccontextmanager`.

---

### P16 — Medium
**Answer:**
**Type hints** (PEP 484) are optional annotations — they do **not** affect runtime behavior; static checkers like `mypy`, `pyright`, and `pyre` use them to catch bugs at edit/build time. The `typing` module provides the vocabulary.

- **`Union[A, B]`** / `A | B` (3.10+) — value is `A` or `B`.
- **`Optional[A]`** — shorthand for `A | None`.
- **`Literal["r", "w"]`** — value must be one of those exact literals; enables exhaustiveness checks and narrows method resolution.
- **`TypeVar("T")`** — a generic type variable for writing parameterized functions/classes (`def first(xs: list[T]) -> T: ...`). Bounds (`bound=Hashable`), variance, and constraints are supported. 3.12+ adds PEP 695 syntax: `def first[T](xs: list[T]) -> T: ...`.
- **`Protocol`** (PEP 544) — structural/duck typing. Anything with the required methods matches, no explicit inheritance needed.

```python
from typing import Protocol, Literal, TypeVar

class SupportsClose(Protocol):
    def close(self) -> None: ...

T = TypeVar("T", bound=SupportsClose)

def close_all(items: list[T]) -> None:
    for i in items:
        i.close()

Mode = Literal["r", "w", "rb", "wb"]
def open_file(path: str, mode: Mode) -> None: ...
```

`mypy`/`pyright` walk the AST, resolve annotations against stubs (`.pyi`) and inline types, and apply flow analysis (narrowing after `isinstance`, `is None`, assertions, `match`) to flag inconsistencies. They catch things like passing `None` to a non-optional parameter, missing return branches, incompatible overrides, and protocol mismatches.

---

### P17 — Medium
**Answer:**
Python's **data model** is the set of "dunder" methods the interpreter calls to implement built-in operations — `+` → `__add__`, `len(x)` → `__len__`, `x[i]` → `__getitem__`, `with x:` → `__enter__`/`__exit__`, etc.

- **`__repr__` vs `__str__`**: `__repr__` is the unambiguous developer representation (used by the REPL, debuggers, `repr(x)`). Aim for something like `ClassName(field=…)`. `__str__` is the user-friendly version (`str(x)`, `print(x)`, f-strings by default). If you only define one, define `__repr__`; `str` falls back to it.
- **`__eq__` vs `__hash__`**: `__eq__` defines value equality. `__hash__` must be consistent with it — equal objects must hash equal. If you override `__eq__` and don't override `__hash__`, Python automatically sets `__hash__ = None`, making instances **unhashable** (can't go in sets / dict keys). If you want hashability, override both, and only hash fields that are also compared in `__eq__`. Mutable objects usually shouldn't be hashable.
- **`__getattr__` vs `__getattribute__`**: `__getattribute__` is called for **every** attribute lookup on an instance — overriding it is risky and easy to infinite-loop. `__getattr__` is called **only when normal lookup fails** (the attribute isn't on the instance, class, or bases). Use `__getattr__` for proxies, lazy attributes, dynamic APIs; use `__getattribute__` only when you truly need to intercept every access.

```python
class Point:
    def __init__(self, x, y): self.x, self.y = x, y
    def __repr__(self):  return f"Point(x={self.x!r}, y={self.y!r})"
    def __str__(self):   return f"({self.x}, {self.y})"
    def __eq__(self, other):
        return isinstance(other, Point) and (self.x, self.y) == (other.x, other.y)
    def __hash__(self):  return hash((self.x, self.y))
```

---

### P18 — Hard
**Answer:**
A **descriptor** is any object that implements one or more of `__get__(self, instance, owner)`, `__set__(self, instance, value)`, `__delete__(self, instance)`. When a class attribute is a descriptor, Python routes attribute access on instances through those methods.

- **Data descriptor**: defines `__set__` or `__delete__`. Takes precedence over instance `__dict__`.
- **Non-data descriptor**: only `__get__`. Instance `__dict__` wins if set.

The descriptor protocol is the mechanism behind many built-ins:

- **`property`** — a data descriptor whose `__get__`/`__set__`/`__delete__` invoke the getter/setter/deleter you supplied. `@property` makes method calls look like attribute access.
- **`classmethod`** — a non-data descriptor whose `__get__` binds the function to the *class* and returns a bound method receiving `cls` as the first argument.
- **`staticmethod`** — a non-data descriptor whose `__get__` returns the underlying function unchanged (no `self`/`cls` binding).
- Functions themselves are non-data descriptors: `func.__get__(instance, cls)` is how `instance.method` produces a bound method.

Custom descriptors are great for validated fields, lazy properties, ORM columns, typed attributes:

```python
class Positive:
    def __set_name__(self, owner, name):
        self._name = name
    def __get__(self, obj, objtype=None):
        if obj is None: return self
        return obj.__dict__[self._name]
    def __set__(self, obj, value):
        if value <= 0:
            raise ValueError(f"{self._name} must be > 0")
        obj.__dict__[self._name] = value

class Order:
    quantity = Positive()
    price    = Positive()
    def __init__(self, quantity, price):
        self.quantity = quantity
        self.price = price
```

`__set_name__` (PEP 487) lets the descriptor learn the attribute name it was bound to.

---

### P19 — Hard
**Answer:**
Python's import system resolves `import foo.bar` into a module object and caches it in `sys.modules`. The high-level flow:

1. Check `sys.modules` — if already imported, return it.
2. Walk **meta path finders** in `sys.meta_path` (`BuiltinImporter`, `FrozenImporter`, `PathFinder`).
3. `PathFinder` consults **path entry finders** for each entry in `sys.path` (plus any `__path__` of the parent package). These return a **module spec** describing how to load the module.
4. A **loader** (referenced by the spec) reads the bytecode / source / extension and executes it, installing the result in `sys.modules`.

**Absolute imports** (`import pkg.sub.mod`) resolve from the top of `sys.path`. **Relative imports** (`from . import x`, `from ..utils import y`) resolve relative to the current package's `__name__` — they only work inside a package (a module imported as part of a package hierarchy), not in scripts run directly.

**`sys.path`** is the list of directories (and zipfiles) searched by the default finder. It's seeded from: the script's directory (or `""` in interactive mode), `PYTHONPATH`, site-packages (`site.py`), and anything code appends at runtime.

**`__init__.py`** marks a directory as a **regular package**. It runs when the package is first imported, can expose a curated API, and its `__path__` lists sub-package search locations. Without `__init__.py` you get a **namespace package** (PEP 420) — directories with the same name on multiple `sys.path` entries are merged into a single logical package, but there's no single file that runs first and no way to put package-level code/state in one place.

**Finders** locate a module and return a `ModuleSpec`; **loaders** actually create/execute the module (`create_module`, `exec_module`). The split lets you plug in custom import mechanisms (zip imports, HTTP imports, `.pyc`-only distributions) by installing a finder on `sys.meta_path` or `sys.path_hooks`.

---

### P20 — Hard
**Answer:**
**`dataclasses`** (stdlib, PEP 557, 3.7+) auto-generates `__init__`, `__repr__`, `__eq__`, and optionally `__hash__`, `__order__`, `__match_args__` from class-level annotations:

```python
from dataclasses import dataclass, field

@dataclass(frozen=True, slots=True)
class User:
    id: int
    name: str
    tags: list[str] = field(default_factory=list)

    def __post_init__(self):
        if self.id <= 0:
            raise ValueError("id must be positive")
```

- **`__post_init__`** runs at the end of the generated `__init__` — used for validation or computing derived fields (via `object.__setattr__` if `frozen=True`).
- **`field(default_factory=...)`** supplies a fresh default per instance. You must use it (not `= []`) for mutable defaults — the decorator will refuse `= []` at class creation time.
- **`frozen=True`** makes instances immutable (`__setattr__`/`__delattr__` raise `FrozenInstanceError`) and auto-generates a `__hash__`.
- **Inheritance**: subclasses inherit fields from parent dataclasses; all fields without defaults must come before fields with defaults across the combined hierarchy — which is the most common gotcha. `kw_only=True` (3.10+) sidesteps this by making parameters keyword-only.

Comparisons:

- **`attrs`** — the library that inspired `dataclasses`. More features: converters, validators, `slots=True` historically, `Factory`, deeper customization, better performance on some paths. Use it when you want validators/converters without Pydantic, or in code that must support older Pythons.
- **`pydantic`** (v2) — dataclass-like syntax (`BaseModel`) but with **runtime type validation and coercion**, JSON (de)serialization, schema generation, nested model validation. Built for I/O boundaries: HTTP requests/responses (FastAPI), config files, DB rows. Much heavier than a dataclass; validation has a cost even in v2's Rust core.

**Choose Pydantic when** you're parsing untrusted input — API payloads, env/config, LLM outputs, CLI args — and want declarative validation and schemas for free.

**Choose dataclasses when** you control the data (internal domain model, value objects, test fixtures) and just want boilerplate-free classes without a third-party dependency.

**Choose attrs when** you need more power than dataclasses but don't want Pydantic's validation/serialization baggage.
