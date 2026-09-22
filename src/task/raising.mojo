from std.builtin._coroutine import AnyCoroutine, RaisingCoroutine
from std.memory import ArcPointer, forget_deinit

from ..context import _CoroutineContext
from ..executor import _ExecutorInner
from .common import (
    _COMPLETED_FLAG_TYPE,
    _CompletedFlagPointer,
    _completed_flag_ptr,
    _install_completion_callback,
)


struct RaisingTask[type: Deinitable & Movable, origins: OriginSet](
    Movable where False
):
    """A raising coroutine queued on an `Executor`, and the result — or the
    error — it will produce.

    Immovable: the coroutine writes its result, error, and completion flag
    through pointers into this struct.
    """

    var _executor: ArcPointer[_ExecutorInner]
    var _handle: AnyCoroutine
    var _completed: _COMPLETED_FLAG_TYPE
    var _result: Self.type
    var _error: Error

    def __init__(
        out self,
        var handle: RaisingCoroutine[Self.type, Self.origins],
        var executor: ArcPointer[_ExecutorInner],
    ):
        """Initialize a task with a raising coroutine.

        Takes ownership of the provided coroutine and points it at this
        task's result slot, error slot, and completion flag.

        Args:
            handle: The raising coroutine to execute as a task. Ownership is
                transferred.
            executor: The executor running the coroutine. Ownership is
                transferred.
        """
        self._executor = executor^
        self._completed = _COMPLETED_FLAG_TYPE(0)

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
        handle._set_result_slot(
            Pointer(to=self._result), Pointer(to=self._error)
        )

        _install_completion_callback(
            handle._get_ctx[_CoroutineContext[_CompletedFlagPointer]](),
            _completed_flag_ptr(self._completed),
        )

        self._handle = handle^._take_handle()

    def wait(deinit self) raises -> Self.type:
        """Run the executor until this task completes, then take its result.

        Consumes the task: the flag and the result/error slots it owns die
        with it.

        Raises:
            The error the coroutine raised, if it raised one.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._executor[].wait_until[completed]()

        if self._has_error():
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
        return self._completed.load() != 0

    def _has_error(self) -> Bool:
        """Return True if the completed coroutine raised rather than returned.

        Only valid once the task has completed.
        """
        return __mlir_op.`co.get_results`[_type=__mlir_type.i1](self._handle)
