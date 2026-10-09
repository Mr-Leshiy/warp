from std.builtin._coroutine import AnyCoroutine
from std.sys import size_of


comptime _CoroutineContextCallbackFn[P: TrivialRegisterPassable] = def(
    P
) thin -> None
"""The function a coroutine's context slot calls, with its payload, when the
coroutine exits."""

comptime _CoroutineContextPtr[
    CallbackPayload: TrivialRegisterPassable
] = Pointer[_CoroutineContext[CallbackPayload], MutUntrackedOrigin]
"""Pointer to a coroutine's context slot."""


struct _CoroutineContext[P: TrivialRegisterPassable](TrivialRegisterPassable):
    """A generic completion context, assigned to a coroutine's frame.

    Replaces the stdlib's `_CoroutineContext` in the same slot, so it has to
    keep that shape: a thin callback followed by the pointer-sized payload the
    coroutine passes to it when it completes. Together the two fields must
    total 16 bytes — a thin function pointer plus one pointer-sized `P` — to
    match the size the stdlib reserves for it in the coroutine frame.

    Parameterized over `P` so callers can carry whatever pointer-sized
    payload their callback needs (e.g. a task's completion-flag pointer)
    without `_CoroutineContext` itself knowing about tasks.
    """

    var callback: _CoroutineContextCallbackFn[Self.P]
    var payload: Self.P


@always_inline
def _get_ctx[
    CallbackPayload: TrivialRegisterPassable
](handle: AnyCoroutine) -> _CoroutineContextPtr[CallbackPayload]:
    """Return a pointer to the coroutine's context slot.

    Same as the stdlib's `Coroutine._get_ctx`, but on a raw handle: the slot
    is the callback the coroutine calls when it exits, garbage until set.
    Valid until the coroutine is destroyed.

    Parameters:
        CallbackPayload: The payload the slot's callback is called with; must be
            pointer-sized.

    Args:
        handle: The coroutine.

    Returns:
        A pointer to the coroutine's context slot.
    """
    comptime assert (
        size_of[_CoroutineContext[CallbackPayload]]() == 2 * size_of[Int]()
    ), "context size must be two pointers"
    return {
        _mlir_value = __mlir_op.`co.get_callback_ptr`[
            _type=__mlir_type[
                `!kgen.pointer<`, _CoroutineContext[CallbackPayload], `>`
            ]
        ](handle)
    }
