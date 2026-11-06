from std.memory import ArcPointer, Layout, alloc
from std.os import abort
from std.sys import size_of


@always_inline
def alloc_one[T: AnyType]() -> Pointer[T, MutUntrackedOrigin]:
    """Allocate uninitialized room for one `T` on the heap.

    Free it with `free_one`: a zero-sized `T` gets a dangling pointer that
    `unsafe_free` can't take.
    """
    return alloc(Layout[T](length=1)).unsafe_leak()


@always_inline
def free_one[T: AnyType](ptr: Pointer[T, MutUntrackedOrigin]):
    """Free room allocated by `alloc_one`, without destroying the value."""
    comptime if size_of[T]() != 0:
        ptr.unsafe_free()


def unsafe_arc_take[T: Movable & Deinitable](var arc: ArcPointer[T]) -> T:
    """Move the value out of its only reference, by reaching into the
    `ArcPointer`'s private heap block. Aborts if `arc` is shared.

    Args:
        arc: The only reference to the value. Ownership is transferred.
    """
    if arc.count() != 1 or arc.weak_count() != 0:
        abort("bug: moving the value out of a shared ArcPointer")
    var value = arc.ptr().unsafe_mut_cast[True]().unsafe_take_pointee()
    arc._inner.unsafe_free()
    __mlir_op.`lit.ownership.mark_destroyed`(__get_mvalue_as_litref(arc))
    return value^
