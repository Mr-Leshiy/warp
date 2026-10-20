from std.builtin._coroutine import Coroutine
from std.collections.optional import Optional
from std.memory import ArcPointer

from ..runtime import _RuntimeInner
from .completion import CompletionCallback
from .handle import _TaskHandle


struct Task[
    type: Deinitable & Movable,
    origins: OriginSet,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable where False):
    """A coroutine queued on a `Runtime`, and the result it will produce.

    Immovable: the coroutine writes its result through a pointer into this
    struct.
    """

    var _runtime: ArcPointer[_RuntimeInner]
    var _handle: ArcPointer[_TaskHandle]
    var _result: Self.type

    def __init__(
        out self,
        var coro: Coroutine[Self.type, Self.origins],
        var runtime: ArcPointer[_RuntimeInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ):
        """Initialize a task with a coroutine.

        Takes ownership of the provided coroutine and points it at this task's
        result slot and completion hook.

        Args:
            coro: The coroutine to execute as a task. Ownership is
                transferred.
            runtime: The runtime running the coroutine. Ownership is
                transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. None by default.
        """
        self._runtime = runtime^

        # `_result` isn't actually written yet — the coroutine writes it,
        # through the pointer handed to `_set_result_slot` below — but every
        # field must be initialized by the end of `__init__`, so this stands
        # in until then.
        __mlir_op.`lit.ownership.mark_initialized`(
            __get_mvalue_as_litref(self._result)
        )
        coro._set_result_slot(Pointer(to=self._result))

        self._handle = ArcPointer(_TaskHandle(coro^._take_handle(), callback^))

    def wait(deinit self) -> Self.type:
        """Run the runtime until this task completes, then take its result.

        Consumes the task: the hook and the result slot it owns die with it.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._runtime[].wait_until[completed]()

        return self._result^

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion.

        A task that has not started, or that is parked on an `await`, reads as
        False; once True, the result is there.
        """
        return self._handle[].is_completed()

    def handle(self) -> ArcPointer[_TaskHandle]:
        """Return a new reference to this task's coroutine and completion
        hook.

        Returns:
            The shared task handle, for queueing on a runtime.
        """
        return self._handle.copy()
