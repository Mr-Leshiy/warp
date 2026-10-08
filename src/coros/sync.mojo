"""The coroutine that synchronizes an executor's device for its tasks."""

from std.memory import ArcPointer
from max.gpu.host import DeviceContext

from ..executor import _ExecutorInner
from ..task import RaisingTask, CompletionCallback


def _spawn_synchronize_coro(executor: ArcPointer[_ExecutorInner]):
    """Queue a coroutine that synchronizes the executor's device, unless one is
    already pending, so concurrent `Context.synchronize` calls share one sync.

    Args:
        executor: The executor whose device to synchronize.
    """

    async def _synchronize(mut ctx: DeviceContext) raises:
        ctx.synchronize()

    # Clears the flag once the sync finishes, so the next sync request
    # spawns a fresh coroutine.
    def _completion_callback(executor: ArcPointer[_ExecutorInner]):
        executor[]._has_sync_coro[] = False

    if not executor[]._has_sync_coro[]:
        executor[]._has_sync_coro[] = True

        var sync_coro = RaisingTask(
            _synchronize(executor[]._ctx),
            executor.copy(),
            CompletionCallback[ArcPointer[_ExecutorInner]](
                _completion_callback, executor.copy()
            ),
        )
        executor[].add(sync_coro.handle())
