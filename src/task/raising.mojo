from std.builtin._coroutine import RaisingCoroutine
from std.collections.optional import Optional
from std.memory import ArcPointer, forget_deinit

from ..executor import _ExecutorInner
from .completion import CompletionCallback
from .handle import _TaskHandle


struct RaisingTask[
    type: Deinitable & Movable,
    origins: OriginSet,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable where False):
    """A raising coroutine queued on an `Executor`, and the result — or the
    error — it will produce.

    Immovable: the coroutine writes its result or error through pointers into
    this struct.
    """

    var _executor: ArcPointer[_ExecutorInner]
    var _handle: ArcPointer[_TaskHandle]
    var _result: Self.type
    var _error: Error

    def __init__(
        out self,
        var coro: RaisingCoroutine[Self.type, Self.origins],
        var executor: ArcPointer[_ExecutorInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ):
        """Initialize a task with a raising coroutine.

        Takes ownership of the provided coroutine and points it at this
        task's result slot, error slot, and completion hook.

        Args:
            coro: The raising coroutine to execute as a task. Ownership is
                transferred.
            executor: The executor running the coroutine. Ownership is
                transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. None by default.
        """
        self._executor = executor^

        # Neither slot is actually written yet — the coroutine writes
        # whichever one it completes with, through the pointers handed to
        # `_set_result_slot` below — but every field must be initialized by
        # the end of `__init__`, so this stands in until then.
        __mlir_op.`lit.ownership.mark_initialized`(
            __get_mvalue_as_litref(self._result)
        )
        __mlir_op.`lit.ownership.mark_initialized`(
            __get_mvalue_as_litref(self._error)
        )
        coro._set_result_slot(Pointer(to=self._result), Pointer(to=self._error))

        self._handle = ArcPointer(_TaskHandle(coro^._take_handle(), callback^))

    def wait(deinit self) raises -> Self.type:
        """Run the executor until this task completes, then take its result.

        Consumes the task: the hook and the result/error slots it owns die
        with it.

        Raises:
            The error the coroutine raised, if it raised one.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._executor[].wait_until[completed]()

        # `has_error` reading `_handle` here is also what keeps it — and the
        # hook `completed` reads — alive through the wait above.
        if self._handle[].has_error():
            # `_result` was never written in this case — don't run its
            # destructor over the uninitialized bytes sitting there.
            forget_deinit(self._result^)
            raise self._error^

        # `_error` was never written in this case — same reasoning.
        forget_deinit(self._error^)
        return self._result^

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion.

        A task that has not started, or that is parked on an `await`, reads
        as False; once True, the result or error is there.
        """
        return self._handle[].is_completed()

    def handle(self) -> ArcPointer[_TaskHandle]:
        """Return a new reference to this task's coroutine and completion
        hook.

        Returns:
            The shared task handle, for queueing on an executor.
        """
        return self._handle.copy()
