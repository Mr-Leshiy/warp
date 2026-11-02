"""The typed handle of a `Coroutine` task."""

from std.builtin._coroutine import AnyCoroutine, Coroutine
from std.collections.optional import Optional
from std.memory import alloc
from std.os import abort

from ..completion import CompletionCallback
from .frame import _TaskFrame
from .task_handle import _TypedTaskHandle


struct _CoroutineHandle[type: Deinitable & Movable](_TypedTaskHandle):
    """A coroutine, its completion state, and its heap-allocated result
    slot."""

    var _coro: _TaskFrame
    var _result: Pointer[Self.type, MutUntrackedOrigin]
    """Uninitialized until the coroutine completes."""

    def __init__[
        origins: OriginSet,
        CallbackPayload: Movable & Deinitable = NoneType,
    ](
        out self,
        var coro: Coroutine[Self.type, origins],
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take a coroutine and point it at this handle's result slot."""
        self._result = alloc[Self.type](1)
        coro._set_result_slot(self._result)
        self._coro = _TaskFrame(coro^._take_handle(), callback^)

    def __deinit__(deinit self):
        """Destroy the result, if written, and free its slot."""
        if self._coro.is_completed():
            self._result.unsafe_deinit_pointee()
        self._result.unsafe_free()

    def take_result(deinit self) -> Self.type:
        """Consume the handle and return the result. Aborts unless the
        coroutine has completed."""
        if not self._coro.is_completed():
            abort("bug: took the result of a coroutine that hasn't completed")
        var result = self._result.unsafe_take_pointee()
        self._result.unsafe_free()
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
