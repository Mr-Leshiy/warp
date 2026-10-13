"""The handle a running coroutine has on its runtime and device."""

from max.gpu.host import DeviceBuffer, DeviceContext, HostBuffer
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
    """A coroutine's handle on the runtime running it and on its device."""

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

    @always_inline
    def enqueue_device_buffer[
        dtype: DType
    ](self, data: Span[Scalar[dtype], _]) raises -> DeviceBuffer[dtype]:
        """Enqueues an async copy from the host to a newly allocated device
        buffer. The number of elements copied is determined by the size of
        `data`.

        The copy reads straight from `data`, so the caller must keep it alive
        until `await self.synchronize()` returns.

        Parameters:
            dtype: The element type of the data.

        Args:
            data: The host data to copy.

        Returns:
            The device buffer the data is copied into once the device is
            synchronized.
        """
        var device = self.gpu_ctx().enqueue_create_buffer[dtype](len(data))
        self.gpu_ctx().enqueue_copy(dst_buf=device, src_ptr=data.unsafe_ptr())
        return device^

    @always_inline
    def enqueue_device_buffer[
        dtype: DType, size: Int
    ](self, data: Array[Scalar[dtype], size]) raises -> DeviceBuffer[dtype]:
        """Enqueues an async copy from the host to a newly allocated device
        buffer. The number of elements copied is determined by the size of
        `data`.

        The copy reads straight from `data`, so the caller must keep it alive
        until `await self.synchronize()` returns.

        Parameters:
            dtype: The element type of the data.
            size: The number of elements in `data`.

        Args:
            data: The host data to copy.

        Returns:
            The device buffer the data is copied into once the device is
            synchronized.
        """
        return self.enqueue_device_buffer(Span(data))

    @always_inline
    def enqueue_host_buffer[
        dtype: DType
    ](self, device: DeviceBuffer[dtype]) raises -> HostBuffer[dtype]:
        """Enqueues an async copy from the device to a newly allocated host
        buffer. The number of elements copied is determined by the size of
        `device`.

        The host buffer is pinned, which keeps the copy async; a copy into
        pageable memory would block until it lands, making the following
        `await self.synchronize()` dead weight.

        Parameters:
            dtype: The element type of the data.

        Args:
            device: The device buffer to copy from.

        Returns:
            The host buffer the data is copied into once the device is
            synchronized.
        """
        var host = self.gpu_ctx().enqueue_create_host_buffer[dtype](len(device))
        self.gpu_ctx().enqueue_copy(dst_buf=host, src_buf=device)
        return host^

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
