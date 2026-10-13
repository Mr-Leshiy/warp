from max.gpu.host import DeviceContext
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
    _assert_aborts,
)

from warp.context import Context
from warp.runtime import Runtime


__async def _yield_once(context: Context) -> Int:
    __await context.synchronize()
    return 1


def test_awaiting_context_from_a_different_runtime_does_not_complete_the_task() raises:
    def __inner__() raises -> None:
        with DeviceContext() as ctx:
            var runtime1 = Runtime(ctx)
            var runtime2 = Runtime(ctx)
            var context2 = runtime2.context()

            # Queued on runtime1, but the coroutine awaits a `Context` that
            # belongs to runtime2, which isn't running it -- so its yield
            # aborts (see `Context.synchronize`'s docstring).
            var task = runtime1.add(_yield_once(context2))

            runtime1.wait()
            # Keeps `task` alive through the wait: it's immovable because the
            # coroutine writes its result into it, so destroying it early
            # leaves the coroutine writing to freed memory.
            _ = task.is_completed()

    _assert_aborts(
        __inner__,
        contains="a coroutine suspended on a runtime that isn't running it",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
