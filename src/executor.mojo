"""The queue that runs the coroutines and the device context they share."""

from max.gpu.host import DeviceContext
from std.builtin._coroutine import (
    AnyCoroutine,
    Coroutine,
    RaisingCoroutine,
    _coro_resume_fn,
    _coro_destroy_fn,
)
from std.collections import Deque
from std.memory import ArcPointer, OwnedPointer

from .context import Context
from .task import RaisingTask, Task


# TODO: revisit `Copyable` (added so tests can hand coroutines their own
# executor handle); consider making `Executor` `Movable` only again.
struct Executor(Copyable):
    """Runs coroutines that share one GPU device context.

    Tasks are queued by `add` and only make progress inside `wait`, which
    resumes them in turn until every one of them has completed. Copies share
    the same queue and device context.
    """

    var _inner: ArcPointer[_ExecutorInner]

    def __init__(out self, ctx: DeviceContext):
        """Initialize an executor running its tasks on the given device.

        Args:
            ctx: The device context shared by every task on this executor.
        """
        self._inner = ArcPointer(_ExecutorInner(ctx))

    def context(self) -> Context:
        """Return a context that coroutines use to reach this executor."""
        return Context(self._inner.copy())

    def add[
        type: Deinitable & Movable, origins: OriginSet
    ](
        mut self,
        var handle: Coroutine[type, origins],
        out task: Task[type, origins],
    ):
        """Queue a coroutine and return the task tracking it.

        The coroutine is not started here: `wait` is what runs it.

        Args:
            handle: The coroutine to run. Ownership is transferred.
        """
        task = Task(handle^, self._inner.copy())
        self._inner[].add(task._handle)

    def add[
        type: Deinitable & Movable, origins: OriginSet
    ](
        mut self,
        var handle: RaisingCoroutine[type, origins],
        out task: RaisingTask[type, origins],
    ):
        """Queue a raising coroutine and return the task tracking it.

        The coroutine is not started here: `wait` is what runs it. Its error,
        if it raises one, surfaces from the returned task's `wait`.

        Args:
            handle: The raising coroutine to run. Ownership is transferred.
        """
        task = RaisingTask(handle^, self._inner.copy())
        self._inner[].add(task._handle)

    def add(self, handle: AnyCoroutine):
        """Queue a bare coroutine handle, without a task tracking it.

        Note:
            A suspend body that only calls this is straight-line code, which
            can trigger a compiler crash
            (https://github.com/modular/modular/issues/7257): a small `raises`
            coroutine that suspends this way gets inlined into the `raises`
            coroutine awaiting it, and lowering fails with
            `'pop.cast_from_builtin' op cannot convert to scalar dtype bool`.
            To work around it on the caller side, mark the awaited `raises`
            coroutine `@no_inline`:

            ```mojo
            @no_inline
            async def inner(executor: Executor) raises -> Int:
                await suspend(executor)  # suspends via `executor.add(hdl)`
                raise Error("failure")

            async def outer(executor: Executor) raises -> Int:
                return await inner(executor)
            ```

        Args:
            handle: The coroutine to resume. The caller keeps ownership of it.
        """
        self._inner[].add(handle)

    def wait(self) raises:
        """Run queued tasks until all have completed, then sync the device."""
        self._inner[].wait()


struct _ExecutorInner:
    """The executor state shared between the `Executor` and its `Context`s."""

    var _ctx: DeviceContext

    # The queue has to stay behind a pointer. `wait` takes `mut self` — an
    # exclusive, `noalias` borrow — yet a coroutine it resumes reaches this
    # same object through the `Context`'s executor pointer to enqueue itself.
    # Stored inline, the deque header would sit in that exclusively borrowed
    # memory and may be cached in registers across the resume, silently
    # dropping the append. Behind a pointer the header lives outside that
    # borrow and both paths agree on it. Note that the queue is genuinely
    # shared-mutable across those two paths, so `OwnedPointer`'s uniqueness
    # claim is a fiction the optimizer is free to act on. `_sync_counter`
    # below is read and written through the same two paths, for the same
    # reason, so it lives behind a pointer too.
    # (Analysis by Claude)
    var _q: OwnedPointer[Deque[AnyCoroutine]]

    var _has_gpu_sync_coro: OwnedPointer[Bool]

    def __init__(out self, ctx: DeviceContext):
        """Initialize the shared state with an empty queue.

        Args:
            ctx: The device context shared by every task on this executor.
        """
        self._ctx = ctx
        self._q = OwnedPointer(Deque[AnyCoroutine]())
        self._has_gpu_sync_coro = OwnedPointer(False)

    def __deinit__(deinit self):
        """Destroy every coroutine still queued."""
        try:
            while len(self._q[]) > 0:
                var handle = self._q[].popleft()
                _coro_destroy_fn(handle)
        except:
            pass

    def add(mut self, handle: AnyCoroutine):
        """Queue a coroutine: freshly created, or resuming after a yield.

        Args:
            handle: The coroutine to run. The caller keeps ownership of it.
        """
        self._q[].append(handle)

    def wait(mut self) raises:
        """Run queued coroutines until all have completed."""

        @__parameter
        def never() -> Bool:
            return False

        self.wait_until[never]()

    @no_inline
    def wait_until[predicate: def() thin capturing -> Bool](mut self) raises:
        """Run queued coroutines until `predicate` holds or the queue empties.

        Synchronizes the device lazily: once, right before resuming the
        first queued coroutine that's waiting on one — not before every
        resume, and not unconditionally after the loop.
        """

        while not predicate() and len(self._q[]) > 0:
            var handle = self._q[].popleft()
            _coro_resume_fn(handle)
