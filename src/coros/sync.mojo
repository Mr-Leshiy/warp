from std.memory import ArcPointer
from max.gpu.host import DeviceContext

from ..executor import _ExecutorInner
from ..task import RaisingTask, CompletionCallback


def _spawn_synchronize_coro(executor: ArcPointer[_ExecutorInner]):
    async def _synchronize(mut ctx: DeviceContext) raises:
        ctx.synchronize()

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
        executor[].add(sync_coro._handle)
