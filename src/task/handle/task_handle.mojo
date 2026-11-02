"""The type-erased task handle the runtime queues: any typed handle behind
an `ErasedOwnedPointer`, driven through a hand-built vtable."""

from std.builtin._coroutine import AnyCoroutine
from std.os import abort

from std.memory import ArcPointer

from ...utils import ErasedOwnedPointer, unsafe_arc_take


trait _TypedTaskHandle(Deinitable, Movable):
    """What the runtime needs from a typed task handle
    (`_CoroutineHandle`, `_RaisingCoroutineHandle`): the operations
    `_TaskHandleVTable` dispatches to."""

    def resume(self):
        """Resume the task from the frame it last suspended in."""
        ...

    def set_resume_at(mut self, frame: AnyCoroutine):
        """Record the frame that suspended, so the next resume picks up there.

        Args:
            frame: The suspended frame. The task keeps owning it.
        """
        ...

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion and its
        callback, if any, has run."""
        ...

    def addr(self) -> String:
        """Return the address of the task's own coroutine frame, for logging."""
        ...

    def resume_addr(self) -> String:
        """Return the address of the frame the next resume picks up in, for
        logging."""
        ...


@fieldwise_init
struct _TaskHandleVTable(ImplicitlyCopyable, Movable):
    """The operations of one typed task handle, each taking the handle
    behind an `ErasedOwnedPointer`: an emulated vtable.

    There's no `drop` entry: `ErasedOwnedPointer` already carries the typed
    handle's destructor, and runs it when the `_TaskHandle` is dropped.
    """

    var resume: def(ErasedOwnedPointer) thin -> None
    var set_resume_at: def(ErasedOwnedPointer, AnyCoroutine) thin -> None
    var is_completed: def(ErasedOwnedPointer) thin -> Bool
    var addr: def(ErasedOwnedPointer) thin -> String
    var resume_addr: def(ErasedOwnedPointer) thin -> String

    @staticmethod
    def of[H: _TypedTaskHandle]() -> Self:
        """Return the vtable of the typed handle `H`.

        Each entry reads the erased pointer as an `H` unchecked: a
        `_TaskHandle` only ever pairs a vtable with a pointer to the same `H`.
        """
        return Self(
            resume=_resume[H],
            set_resume_at=_set_resume_at[H],
            is_completed=_is_completed[H],
            addr=_addr[H],
            resume_addr=_resume_addr[H],
        )


def _resume[H: _TypedTaskHandle](handle: ErasedOwnedPointer):
    handle.unsafe_get[H]()[].resume()


def _set_resume_at[
    H: _TypedTaskHandle
](handle: ErasedOwnedPointer, frame: AnyCoroutine):
    handle.unsafe_get[H]()[].set_resume_at(frame)


def _is_completed[H: _TypedTaskHandle](handle: ErasedOwnedPointer) -> Bool:
    return handle.unsafe_get[H]()[].is_completed()


def _addr[H: _TypedTaskHandle](handle: ErasedOwnedPointer) -> String:
    return handle.unsafe_get[H]()[].addr()


def _resume_addr[H: _TypedTaskHandle](handle: ErasedOwnedPointer) -> String:
    return handle.unsafe_get[H]()[].resume_addr()


struct _TaskHandle(Movable):
    """A task's typed handle, its type erased.

    Has no type parameters, so the handles of any tasks fit in one `List` or
    queue. Owns the typed handle — and with it the coroutine, its completion
    state, and its result — on the heap; dropping this drops all of them.
    """

    var _handle: ErasedOwnedPointer
    var _vtable: _TaskHandleVTable

    def __init__[H: _TypedTaskHandle](out self, var handle: H):
        """Move a typed handle onto the heap and take ownership of it.

        Args:
            handle: The typed handle. Ownership is transferred.
        """
        self._vtable = _TaskHandleVTable.of[H]()
        self._handle = ErasedOwnedPointer(handle^)

    def to_inner[H: _TypedTaskHandle](deinit self) -> H:
        """Consume the handle and move the typed handle out of it.

        Aborts if `H` isn't the type this handle was built with: the task
        that built it is the only one asking for its type, so that would be
        a bug.
        """
        return _typed_handle_from[H](self._handle^)

    def set_resume_at(mut self, frame: AnyCoroutine):
        """Record the frame that suspended, so the next resume picks up there.

        A task suspends in whichever frame hit the yield: its own coroutine or
        one it's awaiting. Resuming the task's own frame instead would carry
        it past its `await` as if the awaited coroutine had completed.

        Args:
            frame: The suspended frame. The task keeps owning it.
        """
        self._vtable.set_resume_at(self._handle, frame)

    def addr(self) -> String:
        """Return the address of the task's own coroutine frame, for logging."""
        return self._vtable.addr(self._handle)

    def resume_addr(self) -> String:
        """Return the address of the frame the next resume picks up in, for
        logging."""
        return self._vtable.resume_addr(self._handle)

    def resume_coroutine(self):
        """Resume the task from the frame it last suspended in."""
        self._vtable.resume(self._handle)

    def is_completed(self) -> Bool:
        """Return True once the coroutine has run to completion and its
        callback, if any, has run."""
        return self._vtable.is_completed(self._handle)


def _take_typed_handle[
    H: _TypedTaskHandle
](var handle: ArcPointer[_TaskHandle]) -> H:
    """Consume the last reference to a task handle and move its typed handle
    out.

    Aborts if anything else, e.g. the runtime's queue, still holds the
    handle, or if `H` isn't its type.

    Args:
        handle: The only reference to the handle. Ownership is transferred.
    """
    return unsafe_arc_take(handle^).to_inner[H]()


def _typed_handle_from[
    H: _TypedTaskHandle
](var handle: ErasedOwnedPointer) -> H:
    """Move the typed handle out of an erased one, aborting if it isn't an
    `H`. A free function: a `deinit self` method can't consume a field
    inside a `try`."""
    try:
        return handle^.to_inner[H]()
    except e:
        abort(String("bug: not this task's handle type: ", e))
