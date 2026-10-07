struct _CoroutineContext[P: TrivialRegisterPassable](TrivialRegisterPassable):
    """A generic completion context, assigned to a coroutine's frame.

    Replaces the stdlib's `_CoroutineContext` in the same slot, so it has to
    keep that shape: a thin callback followed by the pointer-sized payload the
    coroutine passes to it when it completes. Together the two fields must
    total 16 bytes — a thin function pointer plus one pointer-sized `P` — to
    match the size the stdlib reserves for it in the coroutine frame.

    Parameterized over `P` so callers can carry whatever pointer-sized
    payload their callback needs (e.g. a task's completion-flag pointer)
    without `_CoroutineContext` itself knowing about tasks.
    """

    comptime callback_fn_type = def(Self.P) thin -> None

    var callback: Self.callback_fn_type
    var payload: Self.P
