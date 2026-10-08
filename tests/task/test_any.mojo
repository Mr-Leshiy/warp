"""`AnyTask`: dropping the type-erased handle destroys the value through its
`drop`, exactly once."""

from std.memory import ArcPointer
from std.testing import TestSuite, assert_equal

from warp.task.any import AnyTask, TaskTrait


@fieldwise_init
struct _DropCounter(Movable, TaskTrait):
    """Increments a shared counter when it's dropped."""

    var _counter: ArcPointer[Int]

    def drop(deinit self):
        self._counter[] += 1


def test_dropping_any_task_drops_its_value_once() raises:
    var counter = ArcPointer(0)
    var task = AnyTask(_DropCounter(counter.copy()))
    assert_equal(counter[], 0)

    _ = task^
    assert_equal(counter[], 1)


def test_moving_any_task_does_not_drop_its_value() raises:
    var counter = ArcPointer(0)
    var task = AnyTask(_DropCounter(counter.copy()))
    var moved = task^
    assert_equal(counter[], 0)

    _ = moved^
    assert_equal(counter[], 1)


def test_any_task_behind_arc_drops_with_the_last_reference() raises:
    var counter = ArcPointer(0)
    var first = ArcPointer(AnyTask(_DropCounter(counter.copy())))
    var second = first.copy()

    _ = first^
    assert_equal(counter[], 0)

    _ = second^
    assert_equal(counter[], 1)


def test_dropping_any_task_releases_what_its_value_owns() raises:
    var counter = ArcPointer(0)
    var task = AnyTask(_DropCounter(counter.copy()))
    assert_equal(counter.count(), 2)

    _ = task^
    assert_equal(counter.count(), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
