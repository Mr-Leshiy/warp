from std.builtin._coroutine import Coroutine
from std.collections.optional import Optional
from std.memory import ArcPointer
from std.os import abort

from ..runtime import _RuntimeInner
from ..utils import unsafe_arc_take
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

    def __init__(
        out self,
        var coro: Coroutine[Self.type, Self.origins],
        var runtime: ArcPointer[_RuntimeInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ):
        """Initialize a task with a coroutine.

        Takes ownership of the provided coroutine; its handle owns the result
        slot and completion state.

        Args:
            coro: The coroutine to execute as a task. Ownership is
                transferred.
            runtime: The runtime running the coroutine. Ownership is
                transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. None by default.
        """
        self._runtime = runtime^
        self._handle = ArcPointer(_TaskHandle(coro^, callback^))

    def wait(deinit self) -> Self.type:
        """Run the runtime until this task completes, then take its result.

        Consumes the task: the completion state and the result slot it owns die with it.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._runtime[].wait_until[completed]()

        return _take_result[Self.type](self._handle^)

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion.

        A task that has not started, or that is parked on an `await`, reads as
        False; once True, the result is there.
        """
        return self._handle[].is_completed()

    def handle(self) -> ArcPointer[_TaskHandle]:
        """Return a new reference to this task's coroutine and completion
        state.

        Returns:
            The shared task handle, for queueing on a runtime.
        """
        return self._handle.copy()


def _take_result[
    type: Deinitable & Movable
](var handle: ArcPointer[_TaskHandle]) -> type:
    try:
        var task_handle = unsafe_arc_take(handle^)
        var result = task_handle^.to_result[type]()
        return result^
    except e:
        abort(String("bug: taking a completed task's result failed: ", e))
