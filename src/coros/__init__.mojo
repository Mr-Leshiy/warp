"""Internal coroutines the runtime queues on its own executor, such as the
device sync behind `Context.synchronize`.
"""

from .sync import _spawn_synchronize_coro
