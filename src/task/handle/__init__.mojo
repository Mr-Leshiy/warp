"""Task handles: a task's coroutine, completion state, and result.

`_CoroutineHandle` and `_RaisingCoroutineHandle` are the typed handles, one
per coroutine kind; `_TaskHandle` erases their type so the runtime can queue
any of them.
"""

from .task_handle import (
    _TaskHandle,
    _TaskHandleVTable,
    _TypedTaskHandle,
    _take_typed_handle,
)
from .coroutine_handle import _CoroutineHandle
from .raising_coroutine_handle import _RaisingCoroutineHandle
