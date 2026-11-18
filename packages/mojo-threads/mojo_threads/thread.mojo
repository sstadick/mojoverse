"""Owned jobs: pass a value to a thread and get its result back at join."""

from std.memory import OwnedPointer
from .worker import Worker


struct _State[T: Movable & Deinitable, R: Movable & Deinitable](Movable):
    var input: Optional[Self.T]
    var output: Optional[Self.R]
    var error: Optional[Error]

    def __init__(out self, var value: Self.T):
        self.input = Optional(value^)
        self.output = None
        self.error = None


def _run[
    T: Movable & Deinitable,
    R: Movable & Deinitable,
    //,
    work: def(var T) raises thin -> R,
](address: Int) abi("C") -> Int:
    ref state = Pointer[_State[T, R], MutUntrackedOrigin](unsafe_from_address=address)[]
    try:
        state.output = work(state.input.take())
    except error:
        state.error = error^
    return 0


struct Thread[
    T: Movable & Deinitable,
    R: Movable & Deinitable,
    work: def(var T) raises thin -> R,
](Movable):
    """A running owned job; normally constructed with `spawn[function](value^)`.

    `join()` waits, then returns the result or raises the worker's Error. It
    can be called only once. Destruction also waits, but discards the result
    and any error. There is no detach or cancellation. Moving this handle
    does not move the job's allocation. Do not share a handle across threads.

    The input must own its data, or the caller must arrange the lifetime and
    synchronization of anything it borrows. Mojo does not have a Send trait;
    moving a value containing pointers does not prove thread safety.

    Start the jobs before waiting for their results:

    ```mojo {doctest="thread-results" global=true}
    from mojo_threads import spawn
    from std.testing import assert_equal

    def greet(var name: String) -> String:
        return String("Hello, ", name)

    def main() raises:
        var first = spawn[greet](String("Ada"))
        var second = spawn[greet](String("Grace"))
        assert_equal(first.join(), "Hello, Ada")
        assert_equal(second.join(), "Hello, Grace")
    ```

    Parameters:
        T: Owned input type.
        R: Worker result type.
        work: Noncapturing function that consumes the input and produces the result.
    """

    var _worker: Worker
    var _state: OwnedPointer[_State[Self.T, Self.R]]

    def __init__(out self, var value: Self.T) raises:
        """Move the input into stable storage and start the job.

        Args:
            value: Input transferred to the worker.

        Raises:
            Error: If creating the thread monitor or starting the OS thread fails.
        """
        self._worker = Worker()
        self._state = OwnedPointer(_State[Self.T, Self.R](value^))
        self._worker.unsafe_start[_run[Self.work]](Int(self._state.ptr()))

    def __deinit__(deinit self):
        """Wait for completion and discard any unclaimed result or error."""
        self._worker.join()
        # Keep all input/result/error storage alive until the worker exits.
        _ = self._state^

    def join(mut self) raises -> Self.R:
        """Wait and take the result, propagating errors on the calling thread.

        Returns:
            The value returned by the worker, transferred to the caller.

        Raises:
            Error: The worker's error, or an error if this result was already joined.
        """
        self._worker.join()
        if self._state[].error:
            raise self._state[].error.take()
        if not self._state[].output:
            raise Error("thread result already joined")
        return self._state[].output.take()


def spawn[
    T: Movable & Deinitable,
    R: Movable & Deinitable,
    //,
    work: def(var T) raises thin -> R,
](var value: T) raises -> Thread[T, R, work]:
    """Run a noncapturing function on an owned input in a new OS thread.

    Types are inferred: `spawn[compute](input^)`. Pass multiple inputs in a
    tuple or struct. The function may allocate, perform I/O and raise Error;
    exceptions never cross the C ABI. One job allocation and one pthread are
    created per call, not per element. Use Worker for persistent pipelines.

    Parameters:
        T: Input type, inferred from value.
        R: Result type, inferred from work.
        work: Noncapturing function to run on the new thread.

    Args:
        value: Input transferred to the worker.

    Returns:
        An owned handle; call join to receive the result or worker error.

    Raises:
        Error: If creating the thread monitor or starting the OS thread fails.
    """
    return Thread[T, R, work](value^)
