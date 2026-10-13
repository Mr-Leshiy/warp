from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_equal, assert_false

from warp.runtime import Runtime


# Neither test here drives a task to completion via a real yield -- what's
# under test is `Runtime.wait()`'s own contract (empty queue, called more
# than once, a runtime torn down before draining), not any particular
# task shape. A non-yielding task keeps that decoupled from `Context` and
# its one suspend point, `Context.synchronize()`.
async def _no_yield(value: Int) -> Int:
    return value


def test_runtime_wait_on_empty_queue_and_called_twice() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)

        runtime.wait()
        runtime.wait()

        var task = runtime.add(_no_yield(1))
        runtime.wait()
        # Nothing left queued -- must not hang or error.
        runtime.wait()

        assert_equal(task^.wait(), 1)


def test_runtime_dropped_with_task_still_queued() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)

        # Queued but never driven: neither `task.wait()` nor
        # `runtime.wait()` is called before both go out of scope.
        var task = runtime.add(_no_yield(1))
        assert_false(task.is_completed())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
