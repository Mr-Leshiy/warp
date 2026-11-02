"""The typed handle of a `RaisingCoroutine` task."""

from std.builtin._coroutine import AnyCoroutine, RaisingCoroutine
from std.collections.optional import Optional
from std.os import abort

from ...utils import alloc_one, free_one
from ..completion import CompletionCallback
from .frame import _TaskFrame
from .task_handle import _TypedTaskHandle


struct _RaisingCoroutineHandle[type: Deinitable & Movable](_TypedTaskHandle):
    """A raising coroutine, its completion state, and its heap-allocated
    result and error slots, exactly one of which it writes."""

    var _coro: _TaskFrame
    var _result: Pointer[Self.type, MutUntrackedOrigin]
    """Written if the coroutine returned."""
    var _error: Pointer[Error, MutUntrackedOrigin]
    """Written if the coroutine raised."""

    def __init__[
        origins: OriginSet,
        CallbackPayload: Movable & Deinitable = NoneType,
    ](
        out self,
        var coro: RaisingCoroutine[Self.type, origins],
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take a raising coroutine and point it at this handle's slots."""
        self._result = alloc_one[Self.type]()
        self._error = alloc_one[Error]()
        coro._set_result_slot(self._result, self._error)
        self._coro = _TaskFrame(coro^._take_handle(), callback^)

    def __deinit__(deinit self):
        """Destroy whichever slot was written, if any, and free both."""
        if self._coro.is_completed():
            if self.has_error():
                self._error.unsafe_deinit_pointee()
            else:
                self._result.unsafe_deinit_pointee()
        free_one(self._result)
        free_one(self._error)

    def has_error(self) -> Bool:
        """Return True if the completed coroutine raised."""
        return __mlir_op.`co.get_results`[_type=__mlir_type.i1](
            self._coro.raw()
        )

    def take_result(deinit self) raises -> Self.type:
        """Consume the handle and return the result, or raise the error.
        Aborts unless the coroutine has completed."""
        if not self._coro.is_completed():
            abort("bug: took the result of a coroutine that hasn't completed")
        if self.has_error():
            var error = self._error.unsafe_take_pointee()
            free_one(self._result)
            free_one(self._error)
            raise error^
        var result = self._result.unsafe_take_pointee()
        free_one(self._result)
        free_one(self._error)
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
