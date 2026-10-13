"""The handle a running coroutine has on its runtime."""

from max.gpu.host import DeviceContext
from std.builtin._coroutine import (
    AnyCoroutine,
    _coro_resume_fn,
    _suspend_async,
)
from std.collections import Deque
from std.memory import ArcPointer

from .runtime import _RuntimeInner
from .coros import _spawn_synchronize_coro


struct Context(Movable):
    """A coroutine's handle on the runtime running it.

    Hands out the shared `DeviceContext` and lets the coroutine yield control
    back to the runtime.
    """

    var _runtime: ArcPointer[_RuntimeInner]

    def __init__(out self, var runtime: ArcPointer[_RuntimeInner]):
        """Initialize a context bound to the given runtime.

        Args:
            runtime: The runtime to yield back to. Ownership is transferred.
        """
        self._runtime = runtime^

    def gpu_ctx(self) -> DeviceContext:
        """Return the device context shared by every task on this runtime."""
        return self._runtime[]._ctx

    async def synchronize(self):
        """Suspend the calling coroutine and re-queue it on the runtime.

        This is an async alternative of
        https://mojolang.org/docs/std/gpu/host/device_context/DeviceContext/#synchronize.

        Note:
            Only a coroutine spawned on the runtime this context came from may
            await this. It re-queues the task that runtime is running, so
            awaiting it from anywhere else aborts, since that runtime isn't
            running a task.
        """

        def body(hdl: AnyCoroutine) {self}:
            _spawn_synchronize_coro(self._runtime)
            self._runtime[].requeue_current(hdl)

        _suspend_async(body)


async def _synchronize(mut ctx: DeviceContext) raises:
    ctx.synchronize()
