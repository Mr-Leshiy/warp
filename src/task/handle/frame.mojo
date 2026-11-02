"""The part of a task handle shared by every coroutine kind."""

from std.builtin._coroutine import (
    AnyCoroutine,
    _coro_resume_fn,
    _coro_destroy_fn,
)
from std.collections.optional import Optional
from std.memory.owned_pointer import OwnedPointer

from ..completion import (
    CompletionCallback,
    _CompletionState,
    _allocate_completion_state,
)


struct _TaskFrame(Movable):
    """A task's coroutine, its resume point, and its heap-allocated
    completion state."""

    var _handle: AnyCoroutine
    var _resume_at: AnyCoroutine
    """The frame to resume next: the task's own, or one it awaits."""
    var _state: OwnedPointer[_CompletionState]
    """Heap-allocated, so the frame's pointer to it survives moves."""

    def __init__[
        CallbackPayload: Movable & Deinitable = NoneType,
    ](
        out self,
        var coro_handle: AnyCoroutine,
        var callback: Optional[CompletionCallback[CallbackPayload]],
    ):
        """Take a coroutine whose result slot is already set, and install its
        completion state and callback."""
        self._handle = coro_handle
        self._resume_at = self._handle
        self._state = _allocate_completion_state(self._handle, callback^)

    def __deinit__(deinit self):
        """Destroy the coroutine, then free its completion state."""
        _coro_destroy_fn(self._handle)

    def raw(self) -> AnyCoroutine:
        """Return the task's own coroutine, still owned by this struct."""
        return self._handle

    def set_resume_at(mut self, frame: AnyCoroutine):
        """Record the frame that suspended: the task's own, or one it awaits.
        Resuming any other would skip past the `await`."""
        self._resume_at = frame

    def addr(self) -> String:
        """Return the task's coroutine address, for logging."""
        return _coroutine_address(self._handle)

    def resume_addr(self) -> String:
        """Return the address of the frame to resume next, for logging."""
        return _coroutine_address(self._resume_at)

    def resume(self):
        """Resume the task where it last suspended."""
        _coro_resume_fn(self._resume_at)

    def is_done(self) -> Bool:
        """Return True once the coroutine has finished, so its result or
        error is written, even while its callback is still running."""
        return self._state[].is_done()

    def is_completed(self) -> Bool:
        """Return True once the coroutine and its callback have run."""
        return self._state[].is_completed()


def _coroutine_address(hdl: AnyCoroutine) -> String:
    """Return a coroutine's address, for logging, by reading the opaque
    handle's bytes as an `Int`."""
    return hex(UInt64(Pointer(to=hdl).unsafe_bitcast[Int]()[]))
