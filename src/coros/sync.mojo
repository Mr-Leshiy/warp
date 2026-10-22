"""The coroutine that synchronizes a runtime's device for its tasks."""

from std.memory import ArcPointer
from max.gpu.host import DeviceContext

from ..runtime import _RuntimeInner
from ..task import RaisingTask, CompletionCallback


def _spawn_synchronize_coro(runtime: ArcPointer[_RuntimeInner]):
    """Queue a coroutine that synchronizes the runtime's device, unless one is
    already pending, so concurrent `Context.synchronize` calls share one sync.

    Args:
        runtime: The runtime whose device to synchronize.
    """

    __async def _synchronize(mut ctx: DeviceContext) raises:
        ctx.synchronize()

    # Clears the flag once the sync finishes, so the next sync request
    # spawns a fresh coroutine.
    def _completion_callback(runtime: ArcPointer[_RuntimeInner]):
        runtime[]._has_sync_coro[] = False

    if not runtime[]._has_sync_coro[]:
        runtime[]._has_sync_coro[] = True

        var sync_coro = RaisingTask(
            _synchronize(runtime[]._ctx),
            runtime.copy(),
            CompletionCallback[ArcPointer[_RuntimeInner]](
                _completion_callback, runtime.copy()
            ),
        )
        runtime[].add(sync_coro.handle())
