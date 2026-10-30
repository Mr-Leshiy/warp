from std.memory.owned_pointer import OwnedPointer

comptime _ErasedPtr = MutOpaquePointer[MutUntrackedOrigin]
"""Points at a heap-allocated value, its type erased."""


struct ErasedOwnedPointer(Movable):
    """Owns a heap-allocated value whose type is erased: a type-erased
    `OwnedPointer`.

    Remembers how to destroy the value, so dropping the pointer runs the
    value's real destructor before freeing it.
    """

    var _ptr: _ErasedPtr
    var _deinit: def(_ErasedPtr) thin -> None
    """Destroys and frees `_ptr`; the one operation that needs its type."""

    def __init__[T: Movable & Deinitable](out self, var value: T):
        """Move a value onto the heap and take ownership of it.

        Args:
            value: The value. Ownership is transferred.
        """
        self._ptr = (
            OwnedPointer(value^)
            .unsafe_take_allocation()
            .unsafe_leak()
            .unsafe_bitcast[NoneType]()
        )
        self._deinit = _ptr_deinit[T]

    def __deinit__(deinit self):
        """Destroy and free the value."""
        self._deinit(self._ptr)

    def get[T: Movable & Deinitable](self) -> Pointer[T, MutUntrackedOrigin]:
        """Return the value.

        Only valid if `T` is the type the pointer was built with.
        """
        return self._ptr.unsafe_bitcast[T]()


def _ptr_deinit[T: Movable & Deinitable](ptr: _ErasedPtr):
    """Destroy and free a heap-allocated `T` behind a type-erased pointer."""
    var typed = ptr.unsafe_bitcast[T]()
    typed.unsafe_deinit_pointee()
    typed.unsafe_free()
