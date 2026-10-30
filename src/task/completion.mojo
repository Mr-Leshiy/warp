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


struct CompletionCallback[CallbackPayload: Movable & Deinitable = NoneType](
    Movable
):
    """A function a task calls once its coroutine completes, together with
    the payload it's called with: a hand-built closure.

    `CompletionCallbackFn` is `thin`, so it can't capture anything; the
    payload stands in for its captures. The callback owns it, so e.g. an
    `ArcPointer` payload keeps its pointee alive until the callback is
    dropped. Leave `CallbackPayload` as `NoneType` for a callback that needs
    no state.

    Parameters:
        CallbackPayload: The type of the state passed to the function.
    """

    var function: CompletionCallbackFn[Self.CallbackPayload]
    var payload: Self.CallbackPayload

    def __init__(
        out self,
        function: CompletionCallbackFn[Self.CallbackPayload],
        var payload: Self.CallbackPayload,
    ):
        """Initialize a callback.

        Args:
            function: The function to call.
            payload: Passed to `function` when it's called. Ownership is
                transferred.
        """
        self.function = function
        self.payload = payload^

    def __init__(
        out self, function: CompletionCallbackFn[Self.CallbackPayload]
    ) where Self.CallbackPayload == NoneType:
        """Initialize a callback that needs no state.

        Args:
            function: The function to call, with `None`.
        """
        self.function = function
        self.payload = rebind_var[Self.CallbackPayload](None)

    def __call__(self):
        """Call `function` with `payload`."""
        self.function(self.payload)


struct _CompletionState(Movable):
    """Whether a task's coroutine has completed, and the user callback, if
    any, still to run when it does.

    The coroutine frame's completion hook, `_on_completion`, runs the
    callback and then raises the flag. Lives on the heap, owned by a
    `_TaskHandle`.
    """

    var completed: _COMPLETED_FLAG_TYPE
    var callback: Optional[ErasedOwnedPointer]
    """The `CompletionCallback`, its payload type erased: only
    `_on_completion`, installed alongside it, knows that type."""

    def __init__(out self, var callback: Optional[ErasedOwnedPointer]):
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


def _allocate_completion_state[
    CallbackPayload: Movable & Deinitable
](
    handle: AnyCoroutine,
    var callback: Optional[CompletionCallback[CallbackPayload]],
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
            _completion_callback[CallbackPayload](state[].callback.value())[]()
        state[].completed.store(1)

    var erased = Optional[ErasedOwnedPointer]()
    if callback:
        erased = ErasedOwnedPointer(callback.take())
    var state = OwnedPointer(_CompletionState(erased^))

    var ctx = _get_ctx[_CompletionStatePtr](handle)
    ctx[].callback = _on_completion
    ctx[].payload = Pointer(to=state[]).unsafe_origin_cast[MutUntrackedOrigin]()
    return state^


def _completion_callback[
    CallbackPayload: Movable & Deinitable
](callback: ErasedOwnedPointer) -> Pointer[
    CompletionCallback[CallbackPayload], MutUntrackedOrigin
]:
    """Return the typed callback behind a `_CompletionState`'s erased one.

    Aborts if `callback` doesn't hold a `CompletionCallback[CallbackPayload]`:
    `_allocate_completion_state` installs the two together, so that would be
    a bug.
    """
    try:
        return callback.get[CompletionCallback[CallbackPayload]]()
    except e:
        abort(String("bug: not a completion callback: ", e))
