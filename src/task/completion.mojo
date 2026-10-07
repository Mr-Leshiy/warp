from std.atomic import Atomic
from std.collections.optional import Optional

from .context import _CoroutineContext

comptime _COMPLETED_FLAG_TYPE = Atomic[Scalar[DType.uint8]]
"""Flag type of a task's completion flag: `Atomic` cannot store a `Bool`'s `i1`."""

comptime CompletionCallbackFn[CallbackPayload: Movable & Deinitable] = def(
    CallbackPayload
) thin -> None
"""The function a `CompletionCallback` calls with its payload."""


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


struct _CompletionHook[CallbackPayload: Movable & Deinitable](
    Movable where False
):
    """What a task's coroutine runs on completion: an optional user callback,
    then raising the completed flag.

    Lives in the task; the coroutine frame reaches it through the pointer
    stored as its completion payload. Immovable for the same reason.
    """

    var completed: _COMPLETED_FLAG_TYPE
    var callback: Optional[CompletionCallback[Self.CallbackPayload]]

    def __init__(
        out self,
        var callback: Optional[CompletionCallback[Self.CallbackPayload]],
    ):
        self.completed = _COMPLETED_FLAG_TYPE(0)
        self.callback = callback^

    def is_completed(self) -> Bool:
        return self.completed.load() != 0


comptime _CompletionHookPointer[
    CallbackPayload: Movable & Deinitable
] = Pointer[_CompletionHook[CallbackPayload], MutUntrackedOrigin]
"""Pointer to a task's completion hook, as the coroutine frame holds it."""

comptime _CompletionContextPointer[
    CallbackPayload: Movable & Deinitable
] = Pointer[
    _CoroutineContext[_CompletionHookPointer[CallbackPayload]],
    MutUntrackedOrigin,
]
"""Pointer to a task coroutine's context slot, holding its completion hook."""


@always_inline
def _completion_hook_ptr[
    CallbackPayload: Movable & Deinitable
](hook: _CompletionHook[CallbackPayload]) -> _CompletionHookPointer[
    CallbackPayload
]:
    """Build the untracked pointer a coroutine frame uses to reach a hook."""
    return _CompletionHookPointer[CallbackPayload](
        unsafe_from_address=Int(Pointer(to=hook))
    )


def _install_completion_hook[
    CallbackPayload: Movable & Deinitable
](
    ctx: _CompletionContextPointer[CallbackPayload],
    hook: _CompletionHookPointer[CallbackPayload],
):
    """Install the completion hook in a task coroutine's frame.

    Takes the coroutine's context slot directly (from `_get_ctx`) rather than
    the coroutine itself, so it works for a `Task`'s `Coroutine` or a
    `RaisingTask`'s `RaisingCoroutine` alike — both produce the same
    `_CoroutineContext` shape.

    Args:
        ctx: The coroutine's context slot.
        hook: The hook to run once the coroutine completes.
    """

    def _on_completion(hook: _CompletionHookPointer[CallbackPayload]):
        # The callback runs first, so by the time the flag reads as set,
        # it has already finished.
        if hook[].callback:
            hook[].callback.value()()
        hook[].completed.store(1)

    ctx[].callback = _on_completion
    ctx[].payload = hook
