from max.gpu.host import DeviceContext
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    _assert_aborts,
)

from warp.context import Context
from warp.executor import Executor


async def _yield_once(context: Context) -> Int:
    await context.synchronize()
    return 1


def test_awaiting_context_from_a_different_executor_does_not_complete_the_task() raises:
    def __inner__() raises -> None:
        with DeviceContext() as ctx:
            var executor1 = Executor(ctx)
            var executor2 = Executor(ctx)
            var context2 = executor2.context()

            # Queued on executor1, but the coroutine awaits a `Context` that
            # belongs to executor2, which isn't running it -- so its yield
            # aborts (see `Context.synchronize`'s docstring).
            var task = executor1.add(_yield_once(context2))

            executor1.wait()
            # Keeps `task` alive through the wait: it's immovable because the
            # coroutine writes its result into it, so destroying it early
            # leaves the coroutine writing to freed memory.
            _ = task.is_completed()

    _assert_aborts(
        __inner__,
        contains="a coroutine suspended on an executor that isn't running it",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
