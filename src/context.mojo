"""The handle a running coroutine has on its executor."""

from max.gpu.host import DeviceContext
from std.builtin._coroutine import (
    AnyCoroutine,
    _coro_resume_fn,
    _suspend_async,
)
from std.collections import Deque
from std.memory import ArcPointer

from .executor import _ExecutorInner
from .coros import _spawn_synchronize_coro


struct Context(Movable):
    """A coroutine's handle on the executor running it.

    Hands out the shared `DeviceContext` and lets the coroutine yield control
    back to the executor.
    """

    var _executor: ArcPointer[_ExecutorInner]

    def __init__(out self, var executor: ArcPointer[_ExecutorInner]):
        """Initialize a context bound to the given executor.

        Args:
            executor: The executor to yield back to. Ownership is transferred.
        """
        self._executor = executor^

    def gpu_ctx(self) -> DeviceContext:
        """Return the device context shared by every task on this executor."""
        return self._executor[]._ctx

    async def synchronize(self):
        """Suspend the calling coroutine and re-queue it on the executor.

        This is an async alternative of
        https://mojolang.org/docs/std/gpu/host/device_context/DeviceContext/#synchronize.

        Note:
            Only a coroutine spawned on the executor this context came from may
            await this. It re-queues the task that executor is running, so
            awaiting it from anywhere else aborts, since that executor isn't
            running a task.
        """

        def body(hdl: AnyCoroutine) {self}:
            _spawn_synchronize_coro(self._executor)
            self._executor[].requeue_current(hdl)

        _suspend_async(body)


async def _synchronize(mut ctx: DeviceContext) raises:
    ctx.synchronize()
