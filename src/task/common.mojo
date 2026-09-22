from std.atomic import Atomic

from ..context import _CoroutineContext

comptime _COMPLETED_FLAG_TYPE = Atomic[Scalar[DType.uint8]]
"""Flag type of a task's completion flag: `Atomic` cannot store a `Bool`'s `i1`."""

comptime _CompletedFlagPointer = Pointer[
    _COMPLETED_FLAG_TYPE, MutUntrackedOrigin
]
"""Pointer to a task's completion flag, as the coroutine frame holds it."""


@always_inline
def _completed_flag_ptr(
    completed: _COMPLETED_FLAG_TYPE,
) -> _CompletedFlagPointer:
    """Build the untracked pointer a coroutine frame uses to reach a flag."""
    return _CompletedFlagPointer(unsafe_from_address=Int(Pointer(to=completed)))


def _install_completion_callback(
    ctx: Pointer[_CoroutineContext[_CompletedFlagPointer], MutUntrackedOrigin],
    completed: _CompletedFlagPointer,
):
    """Install the completion callback in a task coroutine's frame.

    Takes the coroutine's context slot directly (from `_get_ctx`) rather than
    the coroutine itself, so it works for a `Task`'s `Coroutine` or a
    `RaisingTask`'s `RaisingCoroutine` alike — both produce the same
    `_CoroutineContext` shape.

    Args:
        ctx: The coroutine's context slot.
        completed: The flag to raise once the coroutine completes.
    """

    def _mark_completed(flag: _CompletedFlagPointer):
        flag[].store(1)

    ctx[].callback = _mark_completed
    ctx[].payload = completed
