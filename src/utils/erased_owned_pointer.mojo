from std.memory import alloc
from std.memory.owned_pointer import OwnedPointer

from .type_id import TypeId

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
    var _type_id: TypeId
    """The type of the value `_ptr` points at."""

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
        self._type_id = TypeId.of[T]()

    def __init__[T: Movable & Deinitable](out self):
        """Allocate room for a `T` on the heap without initializing it.

        Write the value through `get` before the pointer is read from or
        dropped: dropping it runs `T`'s destructor over whatever is there.
        """
        self._ptr = alloc[T](1).unsafe_bitcast[NoneType]()
        self._deinit = _ptr_deinit[T]
        self._type_id = TypeId.of[T]()

    def __deinit__(deinit self):
        """Destroy and free the value."""
        self._deinit(self._ptr)

    def type_id(self) -> TypeId:
        """Return the type of the owned value."""
        return self._type_id

    def get[
        T: Movable & Deinitable
    ](self) raises TypeMismatchError -> Pointer[T, MutUntrackedOrigin]:
        """Return the value.

        Raises:
            TypeMismatchError: If `T` isn't the type the pointer was built
                with.
        """
        if self._type_id != TypeId.of[T]():
            raise TypeMismatchError(
                held=self._type_id, requested=TypeId.of[T]()
            )
        return self._ptr.unsafe_bitcast[T]()

    def unsafe_get[
        T: Movable & Deinitable
    ](self) -> Pointer[T, MutUntrackedOrigin]:
        """Return the value as a `T`, without checking the type it was built
        with.

        Only valid if a `T` really sits at the start of the value, e.g. `T`
        is the held type or the type of its first field.
        """
        return self._ptr.unsafe_bitcast[T]()


@fieldwise_init
struct TypeMismatchError(ImplicitlyCopyable, Writable):
    """Raised by `ErasedOwnedPointer.get` when asked for a type other than
    the one it holds."""

    var held: TypeId
    """The type the pointer holds."""
    var requested: TypeId
    """The type `get` was asked for."""

    def write_to(self, mut writer: Some[Writer]):
        writer.write(
            "ErasedOwnedPointer holds `",
            self.held,
            "`, not `",
            self.requested,
            "`",
        )


def _ptr_deinit[T: Movable & Deinitable](ptr: _ErasedPtr):
    """Destroy and free a heap-allocated `T` behind a type-erased pointer."""
    var typed = ptr.unsafe_bitcast[T]()
    typed.unsafe_deinit_pointee()
    typed.unsafe_free()
