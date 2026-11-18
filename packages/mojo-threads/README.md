# Mojo Threads

Native threads for Mojo 1.2.0 on Linux and macOS. Move an input into a thread,
then join to get its result or error. No C callbacks or pointer casts are
needed for ordinary owned jobs.

## Run a job

```mojo {doctest="owned-job" global=true}
from mojo_threads import spawn
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

## Persistent pipelines

`Worker` is the lower-level API used by Perbase. It keeps the same explicit
monitor, stable-context and shutdown contracts so pipelines can choose their
own queues, backpressure and scheduling without extra job allocations.

`Worker` owns a joinable pthread, mutex and condition variable in one stable
native allocation. `available_parallelism()` respects Linux CPU affinity;
on macOS it uses the online processor count. Threads inherit the platform's
normal scheduling policy. There is no raw-clone implementation, copied TLS,
architecture-specific assembly, spin loop, queue or process-wide signal handler.

## Build and test

```sh
git clone https://github.com/sstadick/mojoverse.git
cd mojoverse/packages/mojo-threads
pixi install --locked
pixi run t
pixi run docs
```

For Git consumers use [Mojoverse dependency setup](https://github.com/sstadick/mojoverse#use-a-dependency)
with `subdirectory = "packages/mojo-threads"`.

The source targets Linux x86-64/AArch64 and Apple Silicon macOS 15+. macOS
requires Xcode command-line tools. Native code uses Clang 18.1.8 on Linux and
Apple Clang on macOS, with `-O3 -march=native`. Built archives are host-tuned;
do not distribute them as universal CPU-compatible binaries. Intel macOS and
Windows are not Mojo 1.2 targets.

Native and isolated installed-consumer tests pass on Linux x86-64 and Apple
Silicon macOS. Linux AArch64 is declared but has not been native-tested.
The build backends are pinned as well as the compiler: floating backend versions
produced different dependency metadata between an old cache and a fresh machine.

Consumers import `spawn`, `Thread`, `Worker` and `available_parallelism` from `mojo_threads` and
link `-Xlinker -L$CONDA_PREFIX/lib -Xlinker -lmojo_threads_native -Xlinker -lpthread`.
The `mojo-threads-native` runtime dependency installs the static archive.
Use `mojo build`, not JIT execution, for static native dependencies.

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

Tests exercise persistent request/reply handoffs, concurrent Mojo allocation,
restart after join, repeated join, and rejection of a duplicate start. Perbase
additionally exercises bounded ordered output and compression-ring reuse.
