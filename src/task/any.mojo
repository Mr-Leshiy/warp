"""Type-erased tasks: a hand-built trait object, since Mojo has no dynamic
traits yet."""

from std.memory.alloc import unsafe_alloc

comptime TaskPtr = MutOpaquePointer[MutUntrackedOrigin]
"""Points at the concrete value an `AnyTask` owns, with its type erased."""


trait TaskTrait(Deinitable):
    """What a value must provide to be held by an `AnyTask`: the operations
    its vtable dispatches to."""

    def drop(deinit self) -> None:
        """Destroy the value: called exactly once, by the `AnyTask` that
        owns it, in place of `__deinit__`."""
        self^.__deinit__()


struct _TaskVTable(TrivialRegisterPassable):
    """The operations an `AnyTask` can run on its value without knowing its
    type, each one instantiated for that type when the `AnyTask` is built."""

    var drop: def(TaskPtr) thin -> None
    """Destroys the value with `T.drop`, then frees its memory."""

    def __init__[T: TaskTrait](out self, t: T):
        self.drop = _drop[T]


def _drop[T: TaskTrait](data: TaskPtr):
    def _consume[T: TaskTrait](var value: T):
        value^.drop()

    var ptr = data.unsafe_bitcast[T]()
    # `T.drop` consumes the value, so it can't be called through `ptr[]`;
    # this hands it the value in place, without moving it.
    ptr.unsafe_deinit_pointee_with(_consume[T])
    ptr.unsafe_free()


struct AnyTask(Movable):
    """A heap-allocated value of any type, plus the vtable to operate on it."""

    var _data: TaskPtr
    var _vtable: _TaskVTable

    def __init__[T: TaskTrait & Movable](out self, var value: T):
        """Move `value` to the heap and erase its type.

        Args:
            value: The value to own. Ownership is transferred.
        """
        var ptr = unsafe_alloc[T](1)
        ptr.unsafe_write(value^)
        self._data = ptr.unsafe_bitcast[NoneType]()
        self._vtable = _TaskVTable(ptr[])

    def __deinit__(deinit self):
        """Drop the owned value through the vtable."""
        self._vtable.drop(self._data)
