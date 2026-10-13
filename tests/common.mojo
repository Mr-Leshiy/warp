"""Helpers shared by the test files."""

from std.builtin._coroutine import AnyCoroutine, _suspend_async

from warp.runtime import Runtime


__async def suspend(runtime: Runtime):
    """Suspend the calling coroutine and re-queue it on `runtime`.

    A plain yield point for tests that only need a coroutine to give up
    control, without `Context.synchronize()`'s device sync on resume.

    Args:
        runtime: The runtime running the calling coroutine.
    """

    def body(hdl: AnyCoroutine) {runtime}:
        runtime.add(hdl)

    _suspend_async(body)
