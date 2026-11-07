"""A task can be moved, or dropped while still queued; its result or error
is destroyed exactly once."""

from std.memory import ArcPointer
from std.testing import TestSuite, assert_equal, assert_raises

from warp.context import Context
from warp.runtime import Runtime

from tests.common import CpuDeviceContext, suspend


@fieldwise_init
struct _Count(Movable):
    """A shared counter; a struct, as async functions can't borrow an
    `ArcPointer`."""

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
    # Built before raising, so on the error path this local is dropped once
    # while unwinding, and the unwritten result slot must not be dropped.
    var value = _DropCounter(count._inner.copy())
    if should_raise:
        raise Error("boom")
    return value^


def test_moved_task_still_returns_its_result() raises:
    with CpuDeviceContext() as ctx:
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
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        _ = runtime.add(_suspends_then_returns(context, count))
        # The task is gone, but the queue still holds its handle: the
        # coroutine runs, and its result is dropped with the handle.
        runtime.wait()
        assert_equal(count._inner[], 1)


def test_raising_task_dropped_before_completion_drops_its_result_once() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        _ = runtime.add(_suspends_then_maybe_raises(context, count, False))
        runtime.wait()
        assert_equal(count._inner[], 1)


def test_raising_task_dropped_before_completion_drops_its_error() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        _ = runtime.add(_suspends_then_maybe_raises(context, count, True))
        # Only the unwound local counts: the error is dropped with the handle,
        # and the unwritten result slot isn't.
        runtime.wait()
        assert_equal(count._inner[], 1)


def test_moved_raising_task_still_raises_its_error() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        var task = runtime.add(
            _suspends_then_maybe_raises(context, count, True)
        )
        var moved = task^
        with assert_raises(contains="boom"):
            _ = moved^.wait()
        assert_equal(count._inner[], 1)


def test_raising_task_returns_its_result() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var count = _Count(ArcPointer(0))

        var task = runtime.add(
            _suspends_then_maybe_raises(context, count, False)
        )
        var result = task^.wait()
        assert_equal(count._inner[], 0)

        _ = result^
        assert_equal(count._inner[], 1)


def test_task_never_run_drops_nothing() raises:
    var count = _Count(ArcPointer(0))
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        _ = runtime.add(_suspends_then_returns(context, count))
        # Dropping the runtime drops the queued handle with its coroutine
        # still unstarted: no result was written, so none is destroyed.
    assert_equal(count._inner[], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
