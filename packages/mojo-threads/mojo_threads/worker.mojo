"""Joinable POSIX worker with a mutex and condition variable.

This is a low-level building block for persistent workers, not a scheduler.
The native allocation never moves. The application owns the shared context,
predicates, cancellation and error transport. Calls preserve pthread semantics.
"""

from std.ffi import external_call


@always_inline
def available_parallelism() -> Int:
    """Return available CPUs (Linux affinity, otherwise online processor count)."""
    return Int(external_call["mt_cpus", Int32]())


struct Worker(Movable):
    """Own a thread handle and monitor; explicitly join before destruction.

    Protect shared predicates with lock/unlock on BOTH sides. Test predicates
    in a loop around wait, which atomically unlocks, sleeps, and relocks.
    notify_all does not release the lock. Do not recursively lock or join while
    holding a lock the worker needs. Destruction of an unjoined worker aborts.
    """

    var _handle: Int

    def __init__(out self) raises:
        self._handle = external_call["mt_worker_new", Int]()
        if not self._handle:
            raise Error("cannot allocate worker monitor")

    def __deinit__(deinit self):
        external_call["mt_worker_free", NoneType](self._handle)

    @always_inline
    def lock(self):
        external_call["mt_lock", NoneType](self._handle)

    @always_inline
    def unlock(self):
        external_call["mt_unlock", NoneType](self._handle)

    @always_inline
    def wait(self):
        external_call["mt_wait", NoneType](self._handle)

    @always_inline
    def notify_all(self):
        external_call["mt_notify_all", NoneType](self._handle)

    def unsafe_start[entry: def(Int) abi("C") thin -> Int](self, context: Int) raises:
        """Start entry(context); its integer result is ignored.

        The caller must keep the context and everything it references alive
        and at stable addresses until join. Synchronize all shared mutations.
        entry must not unwind across the C boundary. Starting an unjoined
        worker raises; a joined worker can be started again.
        """
        var code = external_call["mt_start", Int32](self._handle, materialize[entry](), context)
        if code:
            raise Error(String("pthread_create failed: ", code))

    @always_inline
    def join(self):
        """Wait for a started thread; repeated join on an idle worker is a no-op."""
        external_call["mt_join", NoneType](self._handle)
