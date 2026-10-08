from std.builtin._coroutine import AnyCoroutine, Coroutine, RaisingCoroutine
from std.collections.optional import Optional
from std.memory import ArcPointer, forget_deinit

from ..executor import _ExecutorInner
from .context import _CoroutineContext
from .completion import (
    CompletionCallback,
    _CompletionHook,
    _CompletionHookPointer,
    _completion_hook_ptr,
    _install_completion_hook,
)


struct _TaskState[
    type: Deinitable & Movable,
    origins: OriginSet,
    raising: Bool,
    CallbackPayload: Movable & Deinitable = NoneType,
](Movable where False):
    var _executor: ArcPointer[_ExecutorInner]
    var _handle: AnyCoroutine
    var _hook: _CompletionHook[Self.CallbackPayload]
    var _result: Self.type
    var _error: Error

    comptime _Context = _CoroutineContext[
        _CompletionHookPointer[Self.CallbackPayload]
    ]

    def __init__(
        out self,
        var handle: Coroutine[Self.type, Self.origins],
        var executor: ArcPointer[_ExecutorInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ) where not Self.raising:
        self = Self(
            raw_handle=handle._handle,
            ctx=handle._get_ctx[Self._Context](),
            executor=executor^,
            callback=callback^,
        )
        handle._set_result_slot(Pointer(to=self._result))
        # `self._handle` already holds the raw handle; this just retires the
        # typed wrapper.
        _ = handle^._take_handle()

    def __init__(
        out self,
        var handle: RaisingCoroutine[Self.type, Self.origins],
        var executor: ArcPointer[_ExecutorInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]] = None,
    ) where Self.raising:
        self = Self(
            raw_handle=handle._handle,
            ctx=handle._get_ctx[Self._Context](),
            executor=executor^,
            callback=callback^,
        )
        handle._set_result_slot(
            Pointer(to=self._result), Pointer(to=self._error)
        )
        # `self._handle` already holds the raw handle; this just retires the
        # typed wrapper.
        _ = handle^._take_handle()

    def __init__(
        out self,
        *,
        raw_handle: AnyCoroutine,
        ctx: Pointer[Self._Context, MutUntrackedOrigin],
        var executor: ArcPointer[_ExecutorInner],
        var callback: Optional[CompletionCallback[Self.CallbackPayload]],
    ):
        """The construction shared by both coroutine kinds: everything except
        pointing the coroutine at its result slots, which differs by kind and
        is left to the public constructors."""
        self._executor = executor^
        self._handle = raw_handle
        self._hook = _CompletionHook(callback^)

        # Neither slot is actually written yet — the coroutine writes
        # whichever one it completes with, through the pointers the public
        # constructors hand to `_set_result_slot` — but every field must be
        # initialized by the end of `__init__`, so this stands in until then.
        __mlir_op.`lit.ownership.mark_initialized`(
            __get_mvalue_as_litref(self._result)
        )
        __mlir_op.`lit.ownership.mark_initialized`(
            __get_mvalue_as_litref(self._error)
        )

        _install_completion_hook(ctx, _completion_hook_ptr(self._hook))

    def wait(deinit self) raises -> Self.type where Self.raising:
        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._executor[].wait_until[completed]()

        if self._has_error():
            # `_result` was never written in this case — don't run its
            # destructor over the uninitialized bytes sitting there.
            forget_deinit(self._result^)
            raise self._error^

        # `_error` was never written in this case — same reasoning.
        forget_deinit(self._error^)
        return self._result^

    def wait(deinit self) raises -> Self.type where not Self.raising:
        @__parameter
        def completed() -> Bool:
            return self.is_completed()

        self._executor[].wait_until[completed]()
        # `_error` was never written in this case — same reasoning.
        forget_deinit(self._error^)
        return self._result^

    def _has_error(self) -> Bool where Self.raising:
        return __mlir_op.`co.get_results`[_type=__mlir_type.i1](self._handle)

    def is_completed(self) -> Bool:
        return self._hook.is_completed()
