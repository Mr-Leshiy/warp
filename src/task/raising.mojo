from std.builtin._coroutine import RaisingCoroutine
from std.collections.optional import Optional
from std.memory import ArcPointer

from ..runtime import _RuntimeInner
from ..utils import unsafe_arc_take
from .completion import CompletionCallback
from .handle import _RaisingCoroutineHandle, _TaskHandle


struct RaisingTask[
    type: Deinitable & Movable,
    origins: OriginSet,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable):
    """A raising coroutine queued on a `Runtime`, and its result or error."""

    var _runtime: ArcPointer[_RuntimeInner]
    var _handle: ArcPointer[_TaskHandle]

    def __init__(
        out self,
        var coro: RaisingCoroutine[Self.type, Self.origins],
        var runtime: ArcPointer[_RuntimeInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ):
        """Initialize a task with a raising coroutine.

        Args:
            coro: The coroutine to run. Ownership is transferred.
            runtime: The runtime running it. Ownership is transferred.
            callback: Called once the coroutine completes. None by default.
        """
        self._runtime = runtime^
        self._handle = ArcPointer(
            _TaskHandle(_RaisingCoroutineHandle[Self.type](coro^, callback^))
        )

    def wait(deinit self) raises -> Self.type:
        """Run the runtime until this task completes, then return its result.

        Raises:
            The error the coroutine raised, if any.
        """

        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._runtime[].wait_until[completed]()

        return (
            unsafe_arc_take(self._handle^)
            .to_inner[_RaisingCoroutineHandle[Self.type]]()
            .take_result()
        )

    def is_completed(self) -> Bool:
        """Return True once the coroutine has completed."""
        return self._handle[].is_completed()

    def handle(self) -> ArcPointer[_TaskHandle]:
        """Return a new reference to this task's handle, for queueing."""
        return self._handle.copy()
