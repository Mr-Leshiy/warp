"""The handle of a task running a `RaisingCoroutine`."""

from std.builtin._coroutine import AnyCoroutine, RaisingCoroutine
from std.collections.optional import Optional
from std.memory import alloc
from std.os import abort

from ..completion import CompletionCallback
from .frame import _TaskCoroutine
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

    var _coro: _TaskCoroutine
    var _result: Pointer[Self.type, MutUntrackedOrigin]
    """Uninitialized unless the coroutine completed by returning."""
    var _error: Pointer[Error, MutUntrackedOrigin]
    """Uninitialized unless the coroutine completed by raising."""
    var _taken: Bool
    """Whether `take_result` or `take_error` has moved the outcome out."""

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
        self._taken = False
        coro._set_result_slot(self._result, self._error)
        self._coro = _TaskCoroutine(coro^._take_handle(), callback^)

    def __deinit__(deinit self):
        """Destroy whichever slot the coroutine wrote, unless it was already
        taken, then free both slots. The coroutine is destroyed after."""
        if self._coro.is_completed() and not self._taken:
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

    def take_result(mut self) -> Self.type:
        """Move the result out.

        Aborts unless the coroutine has completed by returning and its result
        hasn't been taken yet: otherwise the slot is uninitialized.

        Returns:
            The value the coroutine returned.
        """
        self._take[raised=False]()
        return self._result.unsafe_take_pointee()

    def take_error(mut self) -> Error:
        """Move the error out.

        Aborts unless the coroutine has completed by raising and its error
        hasn't been taken yet: otherwise the slot is uninitialized.

        Returns:
            The error the coroutine raised.
        """
        self._take[raised=True]()
        return self._error.unsafe_take_pointee()

    def _take[raised: Bool](mut self):
        """Mark the outcome taken, aborting unless the coroutine completed
        with that outcome and it hasn't been taken yet."""
        if not self._coro.is_completed():
            abort("bug: took the outcome of a coroutine that hasn't completed")
        if self._taken:
            abort("bug: took the outcome of a coroutine twice")
        if self.has_error() != raised:
            abort("bug: took the wrong outcome of a coroutine")
        self._taken = True

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
