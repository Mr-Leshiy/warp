from std.builtin._coroutine import Coroutine
from std.collections.optional import Optional
from std.memory import ArcPointer

from ..runtime import _RuntimeInner
from .completion import CompletionCallback
from .handle import _CoroutineHandle, _TaskHandle


struct Task[
    type: Deinitable & Movable,
    origins: OriginSet,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable):
    """A coroutine queued on a `Runtime`, and the result it will produce.

    The result is written into the task's handle, which the runtime's queue
    shares, so the task is free to move — or to be dropped before its
    coroutine completes.
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

        Takes ownership of the provided coroutine and hands it to a new
        handle, which holds its result slot and completion state.

        Args:
            coro: The coroutine to execute as a task. Ownership is
                transferred.
            runtime: The runtime running the coroutine. Ownership is
                transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. None by default.
        """
        self._runtime = runtime^
        self._handle = ArcPointer(
            _TaskHandle(_CoroutineHandle[Self.type](coro^, callback^))
        )

    def wait(deinit self) -> Self.type:
        """Run the runtime until this task completes, then take its result.

        Consumes the task: the handle, and the coroutine and completion state
        it owns, die with it unless the runtime still holds them.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._runtime[].wait_until[completed]()

        var handle = self._handle^
        var result = handle[].get[_CoroutineHandle[Self.type]]()[].take_result()
        # `get`'s pointer doesn't keep `handle` alive; dropping it only here
        # keeps the result slot alive through `take_result` above.
        _ = handle^
        return result^

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion.

        A task that has not started, or that is parked on an `await`, reads as
        False; once True, the result is there.
        """
        return self._handle[].is_completed()

    def handle(self) -> ArcPointer[_TaskHandle]:
        """Return a new reference to this task's handle.

        Returns:
            The shared task handle, for queueing on a runtime.
        """
        return self._handle.copy()
