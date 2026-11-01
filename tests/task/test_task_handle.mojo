"""Task handles own their task's result: a `Task` or `RaisingTask` can be
moved, or dropped while its coroutine is still queued, and whatever the
coroutine produces is still destroyed exactly once.
"""

from max.gpu.host import DeviceContext
from std.memory import ArcPointer
from std.testing import TestSuite, assert_equal, assert_raises

from warp.context import Context
from warp.runtime import Runtime

from tests.common import suspend


@fieldwise_init
struct _Count(Movable):
    """A shared counter cell. A struct rather than a bare `ArcPointer`: async
    functions can't take a register-passable argument by borrow."""

    var _inner: ArcPointer[Int]


@fieldwise_init
struct _DropCounter(Movable):
    """Increments a shared counter exactly once, when this value is dropped."""

    var _count: ArcPointer[Int]

    def __deinit__(deinit self):
        self._count[] += 1


__async def _suspends_then_returns(ctx: Context, count: _Count) -> _DropCounter:
    __await suspend(ctx)
    return _DropCounter(count._inner.copy())


__async def _suspends_then_maybe_raises(
    ctx: Context, count: _Count, should_raise: Bool
) raises -> _DropCounter:
    __await suspend(ctx)
    if should_raise:
        raise Error("boom")
    return _DropCounter(count._inner.copy())


def test_moved_task_still_returns_its_result() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        var task = runtime.add(_suspends_then_returns(context, count))
        var moved = task^
        var result = moved^.wait()
        assert_equal(count._inner[], 0)

        _ = result^
        assert_equal(count._inner[], 1)


def test_task_dropped_before_completion_drops_its_result_once() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        _ = runtime.add(_suspends_then_returns(context, count))
        # The task is gone, but the queue still holds its handle: the
        # coroutine runs, and its result is dropped with the handle.
        runtime.wait()
        assert_equal(count._inner[], 1)


def test_raising_task_dropped_before_completion_drops_its_result_once() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        _ = runtime.add(_suspends_then_maybe_raises(context, count, False))
        runtime.wait()
        assert_equal(count._inner[], 1)


def test_raising_task_dropped_before_completion_drops_its_error() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        _ = runtime.add(_suspends_then_maybe_raises(context, count, True))
        # The error is dropped with the handle; the result slot was never
        # written, so nothing runs `_DropCounter`'s destructor.
        runtime.wait()
        assert_equal(count._inner[], 0)


def test_moved_raising_task_still_raises_its_error() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        var task = runtime.add(
            _suspends_then_maybe_raises(context, count, True)
        )
        var moved = task^
        with assert_raises(contains="boom"):
            _ = moved^.wait()
        assert_equal(count._inner[], 0)


def test_task_never_run_drops_nothing() raises:
    var count = _Count(ArcPointer(0))
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        _ = runtime.add(_suspends_then_returns(context, count))
        # Dropping the runtime drops the queued handle with its coroutine
        # still unstarted: no result was written, so none is destroyed.
    assert_equal(count._inner[], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
