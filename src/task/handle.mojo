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
    """Whether dropping this handle destroys the coroutine and its hook."""

    # TODO: get rid of this unsafe hook-less variant. Look into how
    # `_get_ctx` and the frame's context slot work, to find a way
    # to queue only real task handles.
    def __init__(out self, *, coro_handle: AnyCoroutine):
        """Wrap just `coro_handle`: no completion hook, no completed flag, no
        callback.

        Doesn't own the coroutine: dropping this handle doesn't destroy it,
        and `is_completed` always reads False.

        Args:
            coro_handle: The suspended coroutine to resume.
        """
        self._handle = coro_handle
        self._hook = _ErasedCompletionHookPtr.unsafe_dangling()  # never read
        self._hook_deinit = _no_hook_deinit
        self._owns_coroutine = False

    def __init__[
        type: Deinitable & Movable,
        origins: OriginSet,
        CallbackPayload: Movable & Deinitable,
    ](
        out self,
        var coro: Coroutine[type, origins],
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take ownership of a coroutine and install its completion hook.

        Its result slot must already be set (`_set_result_slot`).

        Args:
            coro: The coroutine. Ownership is transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. Ownership is transferred.
        """
        self._handle = coro^._take_handle()
        var hook = _allocate_completion_hook(self._handle, callback^)
        self._hook = hook.unsafe_bitcast[NoneType]()
        self._hook_deinit = _hook_deinit[CallbackPayload]
        self._owns_coroutine = True

    def __init__[
        type: AnyType,
        origins: OriginSet,
        CallbackPayload: Movable & Deinitable,
    ](
        out self,
        var coro: RaisingCoroutine[type, origins],
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take ownership of a raising coroutine and install its completion
        hook.

        Its result and error slots must already be set (`_set_result_slot`).

        Args:
            coro: The raising coroutine. Ownership is transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. Ownership is transferred.
        """
        self._handle = coro^._take_handle()
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
        # `completed` is the hook's first field, whatever its payload type.
        return self._hook.unsafe_bitcast[_COMPLETED_FLAG_TYPE]()[].load() != 0


def _hook_deinit[
    CallbackPayload: Movable & Deinitable
](hook: _ErasedCompletionHookPtr):
    var ptr = hook.unsafe_bitcast[_CompletionHook[CallbackPayload]]()
    ptr.unsafe_deinit_pointee()
    ptr.unsafe_free()


def _no_hook_deinit(hook: _ErasedCompletionHookPtr):
    pass
