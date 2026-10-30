from std.atomic import Atomic
from std.collections.optional import Optional
from std.memory.owned_pointer import OwnedPointer
from std.os import abort

from std.builtin._coroutine import AnyCoroutine

from ..utils import ErasedOwnedPointer
from .context import _CoroutineContextCallbackFn, _get_ctx

comptime _COMPLETED_FLAG_TYPE = Atomic[Scalar[DType.uint8]]
"""Flag type of a task's completion flag: `Atomic` cannot store a `Bool`'s `i1`."""

comptime CompletionCallbackFn[CallbackPayload: Movable & Deinitable] = def(
    CallbackPayload
) thin -> None
"""The function a `CompletionCallback` calls with its payload."""


comptime _CompletionStatePtr = Pointer[_CompletionState, MutUntrackedOrigin]
"""Pointer to a task's completion state, as the coroutine frame holds it."""


struct CompletionCallback(Movable):
    """A function a task calls once its coroutine completes, together with
    the payload it's called with: a hand-built closure.

    `CompletionCallbackFn` is `thin`, so it can't capture anything; the
    payload stands in for its captures. The callback owns it, so e.g. an
    `ArcPointer` payload keeps its pointee alive until the callback is
    dropped.

    The payload's type is erased: it's fixed when the callback is built, so
    neither the callback nor the task it's handed to is parameterized on it.
    """

    var _closure: ErasedOwnedPointer
    """The heap-allocated `_TypedCallback`, its payload type erased."""
    var _call: def(ErasedOwnedPointer) thin -> None
    """Calls `_closure`; the one operation that needs its payload type."""

    def __init__[
        CallbackPayload: Movable & Deinitable
    ](
        out self,
        function: CompletionCallbackFn[CallbackPayload],
        var payload: CallbackPayload,
    ):
        """Initialize a callback.

        Parameters:
            CallbackPayload: The type of the state passed to `function`.

        Args:
            function: The function to call.
            payload: Passed to `function` when it's called. Ownership is
                transferred.
        """
        self._closure = ErasedOwnedPointer(_TypedCallback(function, payload^))
        self._call = _call_typed_callback[CallbackPayload]

    def __init__(out self, function: CompletionCallbackFn[NoneType]):
        """Initialize a callback that needs no state.

        Args:
            function: The function to call, with `None`.
        """
        self = Self(function, None)

    def __call__(self):
        """Call the function with its payload."""
        self._call(self._closure)


@fieldwise_init
struct _TypedCallback[CallbackPayload: Movable & Deinitable](Movable):
    """What a `CompletionCallback` erases: the function and its payload, with
    the payload's type still known."""

    var function: CompletionCallbackFn[Self.CallbackPayload]
    var payload: Self.CallbackPayload


def _call_typed_callback[
    CallbackPayload: Movable & Deinitable
](closure: ErasedOwnedPointer):
    """Call the `_TypedCallback[CallbackPayload]` behind `closure`.

    Aborts if `closure` holds anything else: `CompletionCallback` pairs the
    two, so that would be a bug.
    """
    try:
        ref callback = closure.get[_TypedCallback[CallbackPayload]]()[]
        callback.function(callback.payload)
    except e:
        abort(String("bug: not a completion callback: ", e))


struct _CompletionState(Movable):
    """Whether a task's coroutine has completed, and the user callback, if
    any, still to run when it does.

    The coroutine frame's completion hook, `_on_completion`, runs the
    callback and then raises the flag. Lives on the heap, owned by a
    `_TaskHandle`.
    """

    var completed: _COMPLETED_FLAG_TYPE
    var callback: Optional[CompletionCallback]

    def __init__(out self, var callback: Optional[CompletionCallback]):
        """Initialize a state with the flag cleared.

        Args:
            callback: Run on completion, before the flag is set. Ownership is
                transferred.
        """
        self.completed = _COMPLETED_FLAG_TYPE(0)
        self.callback = callback^

    def is_completed(self) -> Bool:
        """Return whether the coroutine has completed and its callback ran."""
        return self.completed.load() != 0


def _allocate_completion_state(
    handle: AnyCoroutine,
    var callback: Optional[CompletionCallback],
) -> OwnedPointer[_CompletionState]:
    """Allocate a completion state on the heap and install it, with its
    completion hook, in a task coroutine's frame.

    Takes the raw coroutine handle, so it works for a `Task`'s `Coroutine` or
    a `RaisingTask`'s `RaisingCoroutine` alike.

    Args:
        handle: The coroutine.
        callback: Called once the coroutine completes, before the state reads
            as completed. Ownership is transferred.

    Returns:
        The state. Keep it alive for as long as the coroutine may complete.
    """

    def _on_completion(state: _CompletionStatePtr):
        # The callback runs first, so by the time the flag reads as set,
        # it has already finished.
        if state[].callback:
            state[].callback.value()()
        state[].completed.store(1)

    var state = OwnedPointer(_CompletionState(callback^))

    var ctx = _get_ctx[_CompletionStatePtr](handle)
    ctx[].callback = _on_completion
    ctx[].payload = Pointer(to=state[]).unsafe_origin_cast[MutUntrackedOrigin]()
    return state^
