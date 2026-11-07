"""Helpers shared by the test files."""

from std.builtin._coroutine import AnyCoroutine, _suspend_async

from max.gpu.host import DeviceContext
from std.sys.info import CompilationTarget

from warp.context import Context

# The device context the tests run on, so they don't need a GPU.
comptime CpuDeviceContext = DeviceContext[CompilationTarget()]


__async def suspend(ctx: Context):
    """Suspend the calling coroutine and re-queue it on `ctx`'s runtime.

    A plain yield point for tests that only need a coroutine to give up
    control, without `Context.synchronize()`'s device sync on resume.

    Args:
        ctx: The context of the runtime running the calling coroutine.
    """

    def body(hdl: AnyCoroutine) {ctx}:
        ctx._runtime[].requeue_current(hdl)

    _suspend_async(body)
