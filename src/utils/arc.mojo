from std.memory import ArcPointer
from std.os import abort


def unsafe_arc_take[T: Movable & Deinitable](var arc: ArcPointer[T]) -> T:
    """Consume the only reference to a value and move the value out of it.

    `ArcPointer` has no way to move its value out, so this reaches into its
    private heap block: the value is moved out, the block freed, and `arc`
    marked destroyed so its destructor doesn't run over the moved-out value.

    Aborts if `arc` isn't the only reference, strong or weak.

    Args:
        arc: The only reference to the value. Ownership is transferred.
    """
    if arc.count() != 1 or arc.weak_count() != 0:
        abort("bug: moving the value out of a shared ArcPointer")
    var value = arc.ptr().unsafe_mut_cast[True]().unsafe_take_pointee()
    arc._inner.unsafe_free()
    __mlir_op.`lit.ownership.mark_destroyed`(__get_mvalue_as_litref(arc))
    return value^
