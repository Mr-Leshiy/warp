"""A single-threaded async runtime for coroutines that drive a GPU.

A `Runtime` owns a `DeviceContext` and runs the `Task`s added to it; a
coroutine reaches the device through a `Context` and suspends with `await` to
let the others make progress.
"""

from .runtime import Runtime
from .task import Task, RaisingTask
from .context import Context
