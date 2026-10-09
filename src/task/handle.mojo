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
    _CompletionHookPtr,
    _CompletionHook,
    _allocate_completion_hook,
)

comptime _ErasedCompletionHookPtr = MutOpaquePointer[MutUntrackedOrigin]
"""Points at a heap-allocated `_CompletionHook`, its payload type erased."""


struct _TaskHandle(Movable):
    """A task's coroutine and its completion hook.

    Has no type parameters, so the handles of any tasks fit in one `List` or
    queue. The hook lives on the heap, owned by this handle, at the address
    the coroutine frame points at — so the handle itself is free to move.
    """

    var _handle: AnyCoroutine
    var _hook: _ErasedCompletionHookPtr
    var _hook_deinit: def(_ErasedCompletionHookPtr) thin -> None
    """Destroys and frees `_hook`; the one operation that needs its type."""
    var _owns_coroutine: Bool
    """False for a frame re-queued after a yield (see `suspended`)."""

    def __init__(out self, *, suspended: AnyCoroutine):
        """Wrap a frame re-queued after a yield, without owning it.

        A yield hands the executor the frame that suspended: the task's own
        coroutine or one it's awaiting. That frame already belongs to someone,
        and its context slot is in use (the task's hook, or "resume my
        parent"). So this installs no hook and never destroys the frame:
        doing either would cut the task off from its hook, or destroy a frame
        that's still queued, after which resuming it restarts it from the top.

        Args:
            suspended: The suspended frame to resume. Its owner keeps it.
        """
        self._handle = suspended
        self._hook = _ErasedCompletionHookPtr.unsafe_dangling()  # never read
        self._hook_deinit = _hook_deinit[NoneType]  # never called
        self._owns_coroutine = False

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
        var hook = _allocate_completion_hook(self._handle, callback^)
        self._hook = hook.unsafe_bitcast[NoneType]()
        self._hook_deinit = _hook_deinit[CallbackPayload]
        self._owns_coroutine = True

    def __deinit__(deinit self):
        """Destroy the coroutine and free its completion hook, if this handle
        owns them."""
        if self._owns_coroutine:
            self._hook_deinit(self._hook)
            _coro_destroy_fn(self._handle)

    def resume_coroutine(self):
        _coro_resume_fn(self._handle)

    def has_error(self) -> Bool:
        """Return True if the completed coroutine raised rather than returned.

        Only valid for a raising coroutine, once it has completed.
        """
        return __mlir_op.`co.get_results`[_type=__mlir_type.i1](self._handle)

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion and its
        callback, if any, has run."""
        if not self._owns_coroutine:
            return False
        return self._hook.unsafe_bitcast[_COMPLETED_FLAG_TYPE]()[].load() != 0


def _hook_deinit[
    CallbackPayload: Movable & Deinitable
](hook: _ErasedCompletionHookPtr):
    var ptr = hook.unsafe_bitcast[_CompletionHook[CallbackPayload]]()
    ptr.unsafe_deinit_pointee()
    ptr.unsafe_free()


def _no_hook_deinit(hook: _ErasedCompletionHookPtr):
    pass
