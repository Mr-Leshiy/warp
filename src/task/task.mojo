from std.builtin._coroutine import AnyCoroutine, Coroutine
from std.collections.optional import Optional
from std.memory import ArcPointer

from ..executor import _ExecutorInner
from .completion import CompletionCallback
from .state import _TaskState


struct Task[
    type: Deinitable & Movable,
    origins: OriginSet,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable where False):
    """A coroutine queued on an `Executor`, and the result it will produce.

    Immovable: the coroutine writes its result and completion hook through
    pointers into this struct.
    """

    var _state: _TaskState[Self.type, Self.origins, False, Self.CallbackPayload]

    def __init__(
        out self,
        var handle: Coroutine[Self.type, Self.origins],
        var executor: ArcPointer[_ExecutorInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ):
        """Initialize a task with a coroutine.

        Takes ownership of the provided coroutine and points it at this task's
        result slot and completion hook.

        Args:
            handle: The coroutine to execute as a task. Ownership is
                transferred.
            executor: The executor running the coroutine. Ownership is
                transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. None by default.
        """
        self._state = _TaskState[
            Self.type, Self.origins, False, Self.CallbackPayload
        ](handle^, executor^, callback^)

    def wait(deinit self) raises -> Self.type:
        """Run the executor until this task completes, then take its result.

        Consumes the task: the flag and the result slot it owns die with it.
        """
        return self._state^.wait()

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion.

        A task that has not started, or that is parked on an `await`, reads as
        False; once True, the result is there.
        """
        return self._state.is_completed()

    def handle(self) -> AnyCoroutine:
        """Return the handle of the coroutine this task runs.

        Returns:
            The coroutine handle, for queueing on an executor.
        """
        return self._state._handle
