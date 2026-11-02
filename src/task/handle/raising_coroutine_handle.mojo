"""The handle of a task running a `RaisingCoroutine`."""

from std.builtin._coroutine import AnyCoroutine, RaisingCoroutine
from std.collections.optional import Optional
from std.memory import alloc
from std.os import abort

from ..completion import CompletionCallback
from .frame import _TaskFrame
from .task_handle import _TypedTaskHandle


struct _RaisingCoroutineHandle[type: Deinitable & Movable](_TypedTaskHandle):
    """A raising coroutine, its completion state, and the result — or the
    error — it writes.

    Both slots live on the heap, at the addresses the coroutine frame writes
    through, so the handle itself is free to move — e.g. into the
    type-erased `_TaskHandle`. The coroutine writes exactly one of them.

    Parameters:
        type: The type of the coroutine's result.
    """

    var _coro: _TaskFrame
    var _result: Pointer[Self.type, MutUntrackedOrigin]
    """Uninitialized unless the coroutine completed by returning."""
    var _error: Pointer[Error, MutUntrackedOrigin]
    """Uninitialized unless the coroutine completed by raising."""

    def __init__[
        origins: OriginSet,
        CallbackPayload: Movable & Deinitable = NoneType,
    ](
        out self,
        var coro: RaisingCoroutine[Self.type, origins],
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take ownership of a raising coroutine and point it at this
        handle's result slot, error slot, and completion state.

        Args:
            coro: The raising coroutine. Ownership is transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. Ownership is transferred.
        """
        self._result = alloc[Self.type](1)
        self._error = alloc[Error](1)
        coro._set_result_slot(self._result, self._error)
        self._coro = _TaskFrame(coro^._take_handle(), callback^)

    def __deinit__(deinit self):
        """Destroy whichever slot the coroutine wrote, if any, then free both
        slots. The coroutine is destroyed after."""
        if self._coro.is_completed():
            if self.has_error():
                self._error.unsafe_deinit_pointee()
            else:
                self._result.unsafe_deinit_pointee()
        self._result.unsafe_free()
        self._error.unsafe_free()

    def has_error(self) -> Bool:
        """Return True if the completed coroutine raised rather than returned.

        Only valid once the coroutine has completed.
        """
        return __mlir_op.`co.get_results`[_type=__mlir_type.i1](
            self._coro.raw()
        )

    def take_result(deinit self) raises -> Self.type:
        """Consume the handle and move the result out of it, or raise the
        error the coroutine raised.

        The coroutine is destroyed with the handle. Aborts unless the
        coroutine has completed: both slots would be uninitialized.

        Returns:
            The value the coroutine returned.

        Raises:
            The error the coroutine raised, if it raised one.
        """
        if not self._coro.is_completed():
            abort("bug: took the result of a coroutine that hasn't completed")
        if self.has_error():
            var error = self._error.unsafe_take_pointee()
            self._result.unsafe_free()
            self._error.unsafe_free()
            raise error^
        var result = self._result.unsafe_take_pointee()
        self._result.unsafe_free()
        self._error.unsafe_free()
        return result^

    def resume(self):
        self._coro.resume()

    def set_resume_at(mut self, frame: AnyCoroutine):
        self._coro.set_resume_at(frame)

    def is_completed(self) -> Bool:
        return self._coro.is_completed()

    def addr(self) -> String:
        return self._coro.addr()

    def resume_addr(self) -> String:
        return self._coro.resume_addr()
