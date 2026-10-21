"""`Task.wait()`: driving a single task's own coroutine to completion.

Unlike `Runtime.wait()` (see `test_runtime_wait.mojo`), `Task.wait()` only
guarantees progress on the task it's called on -- driving the shared
runtime's queue is a side effect, not its contract. These tests exercise
that side effect and the values it returns, without depending on `Runtime`
being drained through any other call first.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from warp.context import Context
from warp.runtime import Runtime

from tests.common import suspend


async def _yield_once(ctx: Context) -> Int:
    await suspend(ctx)
    return 1


async def _yields_twice[VALUE: Int](ctx: Context) -> Int:
    var total = VALUE
    total += await _yield_once(ctx)
    total += await _yield_once(ctx)
    return total


def test_task_completes_with_its_result() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        var task = runtime.add(_yields_twice[5](context))
        assert_false(task.is_completed())

        runtime.wait()

        assert_true(task.is_completed())
        assert_equal(task^.wait(), 7)


def test_task_wait_returns_its_result() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        var first = runtime.add(_yields_twice[5](context))
        var second = runtime.add(_yields_twice[10](context))

        # Neither task's `wait()` is preceded by `runtime.wait()`: each
        # one has to drive the shared queue itself.
        assert_equal(first^.wait(), 7)
        assert_false(second.is_completed())
        assert_equal(second^.wait(), 12)


async def _yield_n_times(ctx: Context, n: Int) -> Int:
    var i = 0
    while i < n:
        await suspend(ctx)
        i += 1
    return n


def test_task_yields_many_times_in_a_row_with_nothing_else_queued() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        # Only one task is ever queued, so every one of its several
        # yields resumes into an otherwise-empty queue -- there's
        # nothing else for the runtime to interleave with in between.
        var task = runtime.add(_yield_n_times(context, 8))

        assert_equal(task^.wait(), 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
