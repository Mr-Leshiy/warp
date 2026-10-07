from std.atomic import Atomic
from std.collections.optional import Optional

from .context import _CoroutineContext

comptime _COMPLETED_FLAG_TYPE = Atomic[Scalar[DType.uint8]]
"""Flag type of a task's completion flag: `Atomic` cannot store a `Bool`'s `i1`."""

comptime CompletionCallbackPayload = Int
"""The value a task hands its callback: whatever state the callback needs,
e.g. an address it casts back to a pointer."""

comptime CompletionCallbackFn = def(Optional[CompletionCallbackPayload]) thin -> None
"""The function a `CompletionCallback` calls with its payload."""


struct CompletionCallback:
    """A function a task calls once its coroutine completes, together with
    the payload it's called with."""

    var function: CompletionCallbackFn
    var payload: Optional[CompletionCallbackPayload]

    def __init__(
        out self,
        function: CompletionCallbackFn,
        payload: Optional[CompletionCallbackPayload] = None,
    ):
        """Initialize a callback.

        Args:
            function: The function to call.
            payload: Passed to `function` when it's called.
        """
        self.function = function
        self.payload = payload

    def __call__(self):
        """Call `function` with `payload`."""
        self.function(self.payload)


struct _CompletionHook(Movable where False):
    """What a task's coroutine runs on completion: an optional user callback,
    then raising the completed flag.

    Lives in the task; the coroutine frame reaches it through the pointer
    stored as its completion payload. Immovable for the same reason.
    """

    var completed: _COMPLETED_FLAG_TYPE
    var callback: Optional[CompletionCallback]

    def __init__(out self, var callback: Optional[CompletionCallback]):
        self.completed = _COMPLETED_FLAG_TYPE(0)
        self.callback = callback^

    def is_completed(self) -> Bool:
        return self.completed.load() != 0


comptime _CompletionHookPointer = Pointer[_CompletionHook, MutUntrackedOrigin]
"""Pointer to a task's completion hook, as the coroutine frame holds it."""


@always_inline
def _completion_hook_ptr(hook: _CompletionHook) -> _CompletionHookPointer:
    """Build the untracked pointer a coroutine frame uses to reach a hook."""
    return _CompletionHookPointer(unsafe_from_address=Int(Pointer(to=hook)))


def _install_completion_hook(
    ctx: Pointer[_CoroutineContext[_CompletionHookPointer], MutUntrackedOrigin],
    hook: _CompletionHookPointer,
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

    def _on_completion(hook: _CompletionHookPointer):
        # The callback runs first, so by the time the flag reads as set,
        # it has already finished.
        if hook[].callback:
            hook[].callback.value()()
        hook[].completed.store(1)

    ctx[].callback = _on_completion
    ctx[].payload = hook
