"""The handle of a task running a non-raising `Coroutine`."""

from std.builtin._coroutine import AnyCoroutine, Coroutine
from std.collections.optional import Optional
from std.memory import alloc
from std.os import abort

from ..completion import CompletionCallback
from .frame import _TaskCoroutine
from .task_handle import _TypedTaskHandle


struct _CoroutineHandle[type: Deinitable & Movable](_TypedTaskHandle):
    """A non-raising coroutine, its completion state, and the result it
    writes.

    The result slot lives on the heap, at the address the coroutine frame
    writes through, so the handle itself is free to move — e.g. into the
    type-erased `_TaskHandle`.

    Parameters:
        type: The type of the coroutine's result.
    """

    var _coro: _TaskCoroutine
    var _result: Pointer[Self.type, MutUntrackedOrigin]
    """Uninitialized until the coroutine completes."""
    var _taken: Bool
    """Whether `take_result` has moved the result out."""

    def __init__[
        origins: OriginSet,
        CallbackPayload: Movable & Deinitable = NoneType,
    ](
        out self,
        var coro: Coroutine[Self.type, origins],
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take ownership of a coroutine and point it at this handle's result
        slot and completion state.

        Args:
            coro: The coroutine. Ownership is transferred.
            callback: Called once the coroutine completes, before the task
                reads as completed. Ownership is transferred.
        """
        self._result = alloc[Self.type](1)
        self._taken = False
        coro._set_result_slot(self._result)
        self._coro = _TaskCoroutine(coro^._take_handle(), callback^)

    def __deinit__(deinit self):
        """Destroy the result, unless it was never written or already taken,
        then free its slot. The coroutine is destroyed after."""
        if self._coro.is_completed() and not self._taken:
            self._result.unsafe_deinit_pointee()
        self._result.unsafe_free()

    def take_result(mut self) -> Self.type:
        """Move the result out.

        Aborts unless the coroutine has completed and the result hasn't been
        taken yet: either would read an uninitialized slot.

        Returns:
            The value the coroutine returned.
        """
        if not self._coro.is_completed():
            abort("bug: took the result of a coroutine that hasn't completed")
        if self._taken:
            abort("bug: took the result of a coroutine twice")
        self._taken = True
        return self._result.unsafe_take_pointee()

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
