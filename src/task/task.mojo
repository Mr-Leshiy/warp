from std.builtin._coroutine import AnyCoroutine, Coroutine
from std.memory import ArcPointer

from ..context import _CoroutineContext
from ..executor import _ExecutorInner
from .common import (
    _COMPLETED_FLAG_TYPE,
    _CompletedFlagPointer,
    _completed_flag_ptr,
    _install_completion_callback,
)


struct Task[type: Deinitable & Movable, origins: OriginSet](
    Movable where False
):
    """A coroutine queued on an `Executor`, and the result it will produce.

    Immovable: the coroutine writes its result and completion flag through
    pointers into this struct.
    """

    var _executor: ArcPointer[_ExecutorInner]
    var _handle: AnyCoroutine
    var _completed: _COMPLETED_FLAG_TYPE
    var _result: Self.type

    def __init__(
        out self,
        var handle: Coroutine[Self.type, Self.origins],
        var executor: ArcPointer[_ExecutorInner],
    ):
        """Initialize a task with a coroutine.

        Takes ownership of the provided coroutine and points it at this task's
        result slot and completion flag.

        Args:
            handle: The coroutine to execute as a task. Ownership is
                transferred.
            executor: The executor running the coroutine. Ownership is
                transferred.
        """
        self._executor = executor^
        self._completed = _COMPLETED_FLAG_TYPE(0)

        # `_result` isn't actually written yet — the coroutine writes it,
        # through the pointer handed to `_set_result_slot` below — but every
        # field must be initialized by the end of `__init__`, so this stands
        # in until then.
        __mlir_op.`lit.ownership.mark_initialized`(
            __get_mvalue_as_litref(self._result)
        )
        handle._set_result_slot(Pointer(to=self._result))

        _install_completion_callback(
            handle._get_ctx[_CoroutineContext[_CompletedFlagPointer]](),
            _completed_flag_ptr(self._completed),
        )

        self._handle = handle^._take_handle()

    def wait(deinit self) raises -> Self.type:
        """Run the executor until this task completes, then take its result.

        Consumes the task: the flag and the result slot it owns die with it.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._executor[].wait_until[completed]()
        return self._result^

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion.

        A task that has not started, or that is parked on an `await`, reads as
        False; once True, the result is there.
        """
        return self._completed.load() != 0
