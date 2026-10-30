"""The part of a task that doesn't depend on its result or callback types."""

from std.builtin._coroutine import (
    AnyCoroutine,
    Coroutine,
    RaisingCoroutine,
    _coro_resume_fn,
    _coro_destroy_fn,
)
from std.collections.optional import Optional

from .completion import (
    CompletionCallback,
    _COMPLETED_FLAG_TYPE,
    _allocate_completion_hook,
)
from ..utils import ErasedOwnedPointer


struct _TaskHandle(Movable):
    """A task's coroutine and its completion hook.

    Has no type parameters, so the handles of any tasks fit in one `List` or
    queue. The hook lives on the heap, owned by this handle, at the address
    the coroutine frame points at — so the handle itself is free to move.
    """

    var _handle: AnyCoroutine
    var _resume_at: AnyCoroutine
    """The frame to resume next: the task's own coroutine, or one it's
    awaiting that suspended (see `set_resume_at`)."""
    var _hook: ErasedOwnedPointer
    """The heap-allocated `_CompletionHook`, its payload type erased."""

    def __init__[
        CallbackPayload: Movable & Deinitable = NoneType,
    ](
        out self,
        var coro_handle: AnyCoroutine,
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take ownership of a coroutine and install its completion hook.

        Its result slot must already be set (`_set_result_slot`).

        Args:
            coro_handle: The coroutine handle. Ownership is transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. Ownership is transferred.
        """
        self._handle = coro_handle
        self._resume_at = self._handle
        self._hook = _allocate_completion_hook(self._handle, callback^)

    def __deinit__(deinit self):
        """Destroy the coroutine; its completion hook is freed after it."""
        _coro_destroy_fn(self._handle)

    def set_resume_at(mut self, frame: AnyCoroutine):
        """Record the frame that suspended, so the next resume picks up there.

        A task suspends in whichever frame hit the yield: its own coroutine or
        one it's awaiting. Resuming the task's own frame instead would carry
        it past its `await` as if the awaited coroutine had completed.

        Args:
            frame: The suspended frame. The task keeps owning it.
        """
        self._resume_at = frame

    def addr(self) -> String:
        """Return the address of the task's own coroutine frame, for logging."""
        return _coroutine_address(self._handle)

    def resume_addr(self) -> String:
        """Return the address of the frame the next resume picks up in, for
        logging."""
        return _coroutine_address(self._resume_at)

    def resume_coroutine(self):
        """Resume the task from the frame it last suspended in."""
        _coro_resume_fn(self._resume_at)

    def has_error(self) -> Bool:
        """Return True if the completed coroutine raised rather than returned.

        Only valid for a raising coroutine, once it has completed.
        """
        return __mlir_op.`co.get_results`[_type=__mlir_type.i1](self._handle)

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion and its
        callback, if any, has run."""
        # The flag is `_CompletionHook`'s first field, so it can be read
        # without knowing the hook's payload type.
        # TODO: stop relying on field layout: Mojo doesn't guarantee fields
        # stay in declaration order, and nothing enforces the flag staying
        # first. Capture the typed read in `__init__` instead (a pointer to
        # the flag, or a `_hook_is_completed[CallbackPayload]` function).
        return self._hook.unsafe_get[_COMPLETED_FLAG_TYPE]()[].load() != 0


def _coroutine_address(hdl: AnyCoroutine) -> String:
    """Return the address of a coroutine handle, for logging.

    `AnyCoroutine` is an opaque MLIR type, not a pointer, so there's no
    direct way to read its bits. Taking a `Pointer` to the local `hdl` and
    reinterpreting *that* as a `Pointer[Int]` gives a view onto the same
    (pointer-sized) bytes, which can then be read as an address.

    Args:
        hdl: The coroutine handle to return the address of.
    """
    return hex(UInt64(Pointer(to=hdl).unsafe_bitcast[Int]()[]))
