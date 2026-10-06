from std.atomic import Atomic
from std.collections.optional import Optional

from ..context import _CoroutineContext

comptime _COMPLETED_FLAG_TYPE = Atomic[Scalar[DType.uint8]]
"""Flag type of a task's completion flag: `Atomic` cannot store a `Bool`'s `i1`."""

comptime TaskCallback = def() thin -> None
"""A function a task calls once its coroutine completes."""


struct _CompletionHook(Movable where False):
    """What a task's coroutine runs on completion: an optional user callback,
    then raising the completed flag.

    Lives in the task; the coroutine frame reaches it through the pointer
    stored as its completion payload. Immovable for the same reason.
    """

    var completed: _COMPLETED_FLAG_TYPE
    var callback: Optional[TaskCallback]

    def __init__(out self, callback: Optional[TaskCallback]):
        self.completed = _COMPLETED_FLAG_TYPE(0)
        self.callback = callback

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
