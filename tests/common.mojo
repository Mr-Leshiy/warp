"""Helpers shared by the test files."""

from std.builtin._coroutine import AnyCoroutine, _suspend_async

from warp.executor import Executor


async def suspend(executor: Executor):
    """Suspend the calling coroutine and re-queue it on `executor`.

    A plain yield point for tests that only need a coroutine to give up
    control, without `Context.synchronize()`'s device sync on resume.

    Args:
        executor: The executor running the calling coroutine.
    """

    def body(hdl: AnyCoroutine) {executor}:
        executor.add(hdl)

    _suspend_async(body)
