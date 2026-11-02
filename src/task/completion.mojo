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
    """Whether a task's coroutine has finished, whether its user callback, if
    any, has run, and that callback while it's still to run.

    The coroutine frame's completion hook, `_on_completion`, raises `done`,
    runs the callback, and then raises `completed`. Lives on the heap, owned
    by a `_TaskFrame`.
    """

    var done: _COMPLETED_FLAG_TYPE
    """Set once the coroutine has finished, so its result (or error) slot is
    written, before the callback runs. Decides whether that slot needs
    destroying."""
    var completed: _COMPLETED_FLAG_TYPE
    """Set once the callback has run too."""
    var callback: Optional[ErasedOwnedPointer]
    """The `CompletionCallback`, its payload type erased: only
    `_on_completion`, installed alongside it, knows that type. Moved out by
    `_on_completion` before it's called."""
    var _dropped: Optional[Pointer[Bool, MutUntrackedOrigin]]
    """While the callback runs, `_on_completion`'s flag to raise if this state
    is destroyed under it: the callback may drop the last reference to the
    task's handle, and with it this state."""

    def __init__(out self, var callback: Optional[ErasedOwnedPointer]):
        """Initialize a state with both flags cleared.

        Args:
            callback: Run on completion, before `completed` is set. Ownership
                is transferred.
        """
        self.done = _COMPLETED_FLAG_TYPE(0)
        self.completed = _COMPLETED_FLAG_TYPE(0)
        self.callback = callback^
        self._dropped = None

    def __deinit__(deinit self):
        """Tell a running `_on_completion`, if any, that this state is gone."""
        if self._dropped:
            self._dropped.value()[] = True

    def is_done(self) -> Bool:
        """Return whether the coroutine has finished, and so written its
        result or error, whether or not its callback has run yet."""
        return self.done.load() != 0

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
        # The coroutine has written its result (or error) by now. Say so
        # before the callback runs, so a handle dropped during the callback
        # still destroys it.
        state[].done.store(1)
        if state[].callback:
            # Moved out, so the callback and its payload outlive the state if
            # the callback drops the task's handle.
            var callback = state[].callback.take()
            var dropped = False
            state[]._dropped = Pointer(to=dropped).unsafe_origin_cast[
                MutUntrackedOrigin
            ]()
            _completion_callback[CallbackPayload](callback)[]()
            if dropped:
                # The state is freed: nothing is left to mark completed.
                return
            state[]._dropped = None
        # The callback runs first, so by the time the flag reads as set,
        # it has already finished.
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
