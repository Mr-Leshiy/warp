"""`ErasedOwnedPointer` ownership: the value it owns is reachable through
`get`, survives moves of the pointer, and is destroyed exactly once, with its
real destructor, when the pointer is dropped.
"""

from std.memory import ArcPointer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from warp.utils import ErasedOwnedPointer, TypeId, TypeMismatchError


@fieldwise_init
struct _DropCounter(Movable):
    """Increments a shared counter exactly once, when this value is dropped."""

    var _count: ArcPointer[Int]

    def __deinit__(deinit self):
        self._count[] += 1


def test_drop_runs_the_value_destructor_once() raises:
    var count = ArcPointer(0)
    var ptr = ErasedOwnedPointer(_DropCounter(count.copy()))
    assert_equal(count[], 0)

    _ = ptr^
    assert_equal(count[], 1)


def test_get_reads_and_writes_the_owned_value() raises:
    var ptr = ErasedOwnedPointer(String("hello"))
    assert_equal(ptr.get[String]()[], "hello")

    ptr.get[String]()[] += ", world"
    assert_equal(ptr.get[String]()[], "hello, world")

    # `get`'s pointer doesn't keep `ptr` alive; keep it alive past the last
    # read so that read isn't of freed memory.
    _ = ptr^


def test_move_keeps_the_value_and_drops_it_once() raises:
    var count = ArcPointer(0)
    var ptr = ErasedOwnedPointer(_DropCounter(count.copy()))
    var address = Int(ptr.get[_DropCounter]())

    var moved = ptr^
    # Moving the pointer moves the address, not the value behind it.
    assert_equal(Int(moved.get[_DropCounter]()), address)
    assert_equal(count[], 0)

    _ = moved^
    assert_equal(count[], 1)


def test_optional_drops_the_value_only_when_set() raises:
    var count = ArcPointer(0)

    var empty = Optional[ErasedOwnedPointer](None)
    assert_false(Bool(empty))
    _ = empty^
    assert_equal(count[], 0)

    var set = Optional(ErasedOwnedPointer(_DropCounter(count.copy())))
    assert_true(Bool(set))
    _ = set^
    assert_equal(count[], 1)


def test_uninitialized_slot_written_through_get() raises:
    var count = ArcPointer(0)
    var ptr = ErasedOwnedPointer.__init__[_DropCounter]()
    # Write the way a coroutine writes its result: in place, over
    # uninitialized memory.
    ptr.get[_DropCounter]().unsafe_write(_DropCounter(count.copy()))
    assert_equal(count[], 0)

    _ = ptr^
    assert_equal(count[], 1)


def test_type_id_records_the_value_type() raises:
    var ptr = ErasedOwnedPointer(String("hello"))
    assert_true(ptr.type_id() == TypeId.of[String]())
    assert_false(ptr.type_id() == TypeId.of[Int]())

    # `Int` has no destructor to run, so the slot can be dropped unwritten.
    var uninit = ErasedOwnedPointer.__init__[Int]()
    assert_true(uninit.type_id() == TypeId.of[Int]())
    assert_false(uninit.type_id() == TypeId.of[String]())


def test_get_raises_on_the_wrong_type() raises:
    var ptr = ErasedOwnedPointer(String("hello"))
    var raised = False
    try:
        _ = ptr.get[Int]()
    except e:
        raised = True
        assert_true(e.held == TypeId.of[String]())
        assert_true(e.requested == TypeId.of[Int]())
        assert_true(String("not `", TypeId.of[Int](), "`") in String(e))
    assert_true(raised)

    # The right type still reads fine afterwards.
    assert_equal(ptr.get[String]()[], "hello")
    _ = ptr^


def test_to_inner_moves_the_value_out() raises:
    var count = ArcPointer(0)
    var ptr = ErasedOwnedPointer(_DropCounter(count.copy()))

    var value = ptr^.to_inner[_DropCounter]()
    # Moving out doesn't run the destructor; dropping the result does.
    assert_equal(count[], 0)
    _ = value^
    assert_equal(count[], 1)

    var text = ErasedOwnedPointer(String("hello")).to_inner[String]()
    assert_equal(text, "hello")


def test_to_inner_raises_on_the_wrong_type() raises:
    var count = ArcPointer(0)
    var ptr = ErasedOwnedPointer(_DropCounter(count.copy()))
    var raised = False
    try:
        _ = ptr^.to_inner[Int]()
    except e:
        raised = True
        assert_true(e.held == TypeId.of[_DropCounter]())
        assert_true(e.requested == TypeId.of[Int]())
    assert_true(raised)
    # The pointer was consumed, so the value is destroyed even though the
    # move-out failed.
    assert_equal(count[], 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
