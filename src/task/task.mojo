from std.builtin._coroutine import Coroutine
from std.collections.optional import Optional
from std.memory import ArcPointer

from ..runtime import _RuntimeInner
from ..utils import unsafe_arc_take
from .completion import CompletionCallback
from .handle import _CoroutineHandle, _TaskHandle


struct Task[
    type: Deinitable & Movable,
    origins: OriginSet,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable):
    """A coroutine queued on a `Runtime`, and the result it will produce."""

    var _runtime: ArcPointer[_RuntimeInner]
    var _handle: ArcPointer[_TaskHandle]

    def __init__(
        out self,
        var coro: Coroutine[Self.type, Self.origins],
        var runtime: ArcPointer[_RuntimeInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ):
        """Initialize a task with a coroutine.

        Args:
            coro: The coroutine to run. Ownership is transferred.
            runtime: The runtime running it. Ownership is transferred.
            callback: Called once the coroutine completes. None by default.
        """
        self._runtime = runtime^
        self._handle = ArcPointer(
            _TaskHandle(_CoroutineHandle[Self.type](coro^, callback^))
        )

    def wait(deinit self) -> Self.type:
        """Run the runtime until this task completes, then return its result."""

        ref handle = self._handle

        def completed() {imm handle} -> Bool:
            return handle[].is_completed()

        # A copy, so running the runtime doesn't alias `self` borrowed above.
        var runtime = self._runtime.copy()
        runtime[].wait_until(completed)

        return (
            unsafe_arc_take(self._handle^)
            .to_inner[_CoroutineHandle[Self.type]]()
            .take_result()
        )

    def is_completed(self) -> Bool:
        """Return True once the coroutine has completed."""
        return self._handle[].is_completed()
