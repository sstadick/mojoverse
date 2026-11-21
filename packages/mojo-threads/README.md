# Mojo Threads

Native threads for Mojo 1.3.0.dev2026111705 on Linux and macOS. Move an input into a thread,
then join to get its result or error. No C callbacks or pointer casts are
needed for ordinary owned jobs.

[API reference](https://sstadick.github.io/mojoverse/mojo-threads/threads/_index.html)

## Install

Follow the [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
and add this Git dependency to your `pixi.toml`. Replace `<full-commit>` with a
Mojoverse commit and use the same revision for every Mojoverse dependency:

```toml
[dependencies]
mojo-threads = { git = "https://github.com/sstadick/mojoverse.git", rev = "<full-commit>", subdirectory = "packages/mojo-threads" }
```

Run `pixi install`. Consumers import `spawn`, `Thread`, `Worker` and
`available_parallelism` from `threads` and link
`-Xlinker -L$CONDA_PREFIX/lib -Xlinker -lmojo_threads_native -Xlinker -lpthread`.
The `mojo-threads-native` dependency installs the static archive from the same
Git revision; no source `-I` path is needed. Use `mojo build`, not JIT execution,
for static native dependencies.

## Run a job

```mojo {doctest="owned-job" global=true}
from threads import spawn
from std.testing import assert_equal

def total(var values: List[Int]) raises -> Int:
    var result = 0
    for value in values:
        result += value
    return result

def main() raises:
    var job = spawn[total]([10, 20, 12])
    # Other work can run here. The list belongs to the worker now.
    assert_equal(job.join(), 42)
```

`spawn[function](input^)` infers input/result types. Pass several arguments in
a tuple or struct. `join()` waits and returns the result, or raises the worker's
`Error` on the caller. It consumes the result; a second call raises. Dropping
the handle also waits, but discards errors—join explicitly to observe them.
The job's storage remains stable when the handle moves.

Use owning inputs (`List`, `String`, your own structs). There is no `Send`
trait: a struct containing borrowed pointers still needs caller-managed
lifetimes and synchronization. The function is noncapturing; it receives its
state through the input. This API starts one OS thread per call, not a task
pool. Batch small items into one job rather than spawning per item.

## Pass several inputs and run jobs together

Use a struct to name a job's inputs. Start both jobs before joining either;
joining immediately after every spawn would serialize the work.

```mojo {doctest="parallel-jobs" global=true}
from threads import spawn
from std.testing import assert_equal

@fieldwise_init
struct ScaledSum(Movable):
    var values: List[Int]
    var scale: Int

def calculate(var input: ScaledSum) -> Int:
    var total = 0
    for value in input.values:
        total += value
    return total * input.scale

def main() raises:
    var first = spawn[calculate](ScaledSum([2, 5], 3))
    var second = spawn[calculate](ScaledSum([11, -1], 2))
    assert_equal(first.join(), 21)
    assert_equal(second.join(), 20)
```

## Handle a worker error

Catch the error from `join()` on the calling thread. Dropping the handle waits
for completion but discards the error, so join when the outcome matters.

```mojo {doctest="worker-error" global=true}
from threads import spawn
from std.testing import assert_equal, assert_true

def quotient(var inputs: Tuple[Int, Int]) raises -> Int:
    if inputs[1] == 0:
        raise Error("denominator must be nonzero")
    return inputs[0] // inputs[1]

def main() raises:
    var job = spawn[quotient]((42, 0))
    var handled = False
    try:
        _ = job.join()
    except error:
        assert_equal(String(error), "denominator must be nonzero")
        handled = True
    assert_true(handled)
```

## Persistent pipelines

`Worker` provides a thread and synchronization primitives for persistent
pipelines. The caller owns the shared context, queues, backpressure, and
shutdown protocol.

`Worker` owns a joinable pthread, mutex and condition variable in one stable
native allocation. `available_parallelism()` respects Linux CPU affinity;
on macOS it uses the online processor count. Threads inherit the platform's
normal scheduling policy.

## Build and test

```sh
git clone https://github.com/sstadick/mojoverse.git
cd mojoverse/packages/mojo-threads
pixi install --locked
pixi run t
pixi run docs
```

The source targets Linux x86-64/AArch64 and Apple Silicon macOS 15+. macOS
requires Xcode command-line tools. Native code uses Clang 18.1.8 on Linux and
Apple Clang on macOS, with `-O3 -march=native`. Built archives are host-tuned;
do not distribute them as universal CPU-compatible binaries. Intel macOS and
Windows are not Mojo 1.2 targets.

## Low-level Worker contract

`unsafe_start[callback](address)` accepts a nonraising `abi("C")` function
taking and returning `Int`. The return value is ignored. Keep the addressed
context and all referenced allocations alive and stationary until `join()`.
Catch exceptions inside the callback; they must not cross the C ABI boundary.
Starting an unjoined worker raises. After joining, a worker can be restarted.

`lock()` / `unlock()` protect the application's shared predicate and data.
Call `wait()` with the lock held, inside a predicate loop: pthreads may wake
spuriously. It atomically releases the lock and reacquires it before returning.
Call `notify_all()` after changing the predicate. Notification does not unlock.
Do not hold a lock needed by the worker while joining.

The owner must arrange shutdown and explicitly join before destruction.
Destruction of an unjoined worker aborts rather than freeing live state or
silently blocking forever. Start/join/destruction belong to one controlling
thread; lock/wait/notification may be used by the participating threads.
Unexpected pthread synchronization errors abort. This unsafe interface does
not prove callback lifetimes or absence of data races.
