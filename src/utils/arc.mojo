from std.memory import ArcPointer
from std.os import abort


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
