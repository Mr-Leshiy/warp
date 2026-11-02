"""The type-erased task handle the runtime queues."""

from std.builtin._coroutine import AnyCoroutine
from std.os import abort

from ...utils import ErasedOwnedPointer


trait _TypedTaskHandle(Deinitable, Movable):
    """A typed task handle: the operations `_TaskHandleVTable` dispatches to."""

    def resume(self):
        """Resume the task where it last suspended."""
        ...

    def set_resume_at(mut self, frame: AnyCoroutine):
        """Record the frame to resume next."""
        ...

    def is_completed(self) -> Bool:
        """Return True once the coroutine and its callback have run."""
        ...

    def addr(self) -> String:
        """Return the task's coroutine address, for logging."""
        ...

    def resume_addr(self) -> String:
        """Return the address of the frame to resume next, for logging."""
        ...


@fieldwise_init
struct _TaskHandleVTable(ImplicitlyCopyable, Movable):
    """A typed handle's operations, over its `ErasedOwnedPointer`.

    No `drop` entry: `ErasedOwnedPointer` runs the typed destructor.
    """

    var resume: def(ErasedOwnedPointer) thin -> None
    var set_resume_at: def(ErasedOwnedPointer, AnyCoroutine) thin -> None
    var is_completed: def(ErasedOwnedPointer) thin -> Bool
    var addr: def(ErasedOwnedPointer) thin -> String
    var resume_addr: def(ErasedOwnedPointer) thin -> String

    @staticmethod
    def of[H: _TypedTaskHandle]() -> Self:
        """Return `H`'s vtable. Entries read the pointer as an `H` unchecked."""

        def _resume[H: _TypedTaskHandle](handle: ErasedOwnedPointer):
            handle.unsafe_get[H]()[].resume()

        def _set_resume_at[
            H: _TypedTaskHandle
        ](handle: ErasedOwnedPointer, frame: AnyCoroutine):
            handle.unsafe_get[H]()[].set_resume_at(frame)

        def _is_completed[
            H: _TypedTaskHandle
        ](handle: ErasedOwnedPointer) -> Bool:
            return handle.unsafe_get[H]()[].is_completed()

        def _addr[H: _TypedTaskHandle](handle: ErasedOwnedPointer) -> String:
            return handle.unsafe_get[H]()[].addr()

        def _resume_addr[
            H: _TypedTaskHandle
        ](handle: ErasedOwnedPointer) -> String:
            return handle.unsafe_get[H]()[].resume_addr()

        return Self(
            resume=_resume[H],
            set_resume_at=_set_resume_at[H],
            is_completed=_is_completed[H],
            addr=_addr[H],
            resume_addr=_resume_addr[H],
        )


struct _TaskHandle(Movable):
    """A typed task handle with its type erased, so any task fits in one
    queue."""

    var _handle: ErasedOwnedPointer
    var _vtable: _TaskHandleVTable

    def __init__[H: _TypedTaskHandle](out self, var handle: H):
        """Move a typed handle onto the heap."""
        self._vtable = _TaskHandleVTable.of[H]()
        self._handle = ErasedOwnedPointer(handle^)

    def to_inner[H: _TypedTaskHandle](deinit self) -> H:
        """Move the typed handle out. Aborts if it isn't an `H`."""
        return _typed_handle_from[H](self._handle^)

    def set_resume_at(mut self, frame: AnyCoroutine):
        """Record the frame to resume next."""
        self._vtable.set_resume_at(self._handle, frame)

    def addr(self) -> String:
        """Return the task's coroutine address, for logging."""
        return self._vtable.addr(self._handle)

    def resume_addr(self) -> String:
        """Return the address of the frame to resume next, for logging."""
        return self._vtable.resume_addr(self._handle)

    def resume_coroutine(self):
        """Resume the task where it last suspended."""
        self._vtable.resume(self._handle)

    def is_completed(self) -> Bool:
        """Return True once the coroutine and its callback have run."""
        return self._vtable.is_completed(self._handle)


def _typed_handle_from[
    H: _TypedTaskHandle
](var handle: ErasedOwnedPointer) -> H:
    """`_TaskHandle.to_inner`'s body: a `deinit self` method can't consume a
    field inside a `try`."""
    try:
        return handle^.to_inner[H]()
    except e:
        abort(String("bug: not this task's handle type: ", e))
