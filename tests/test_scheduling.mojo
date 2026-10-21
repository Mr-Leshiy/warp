"""Multiple tasks sharing one `Runtime`: outcome correctness under
whatever interleaving the scheduler happens to pick.

Ground rule: these tests assert on outcomes only -- final results, shared
state, completion -- never on the runtime's internal resume order, which
is an implementation detail, not a contract.
"""

from max.gpu.host import DeviceContext
from std.memory import OwnedPointer
from std.testing import TestSuite, assert_equal, assert_true

from warp.context import Context
from warp.runtime import Runtime

from tests.common import suspend


async def _yield_once(ctx: Context) -> Int:
    await suspend(ctx)
    return 1


async def _yields_twice[VALUE: Int](ctx: Context) -> Int:
    var total = VALUE
    total += await _yield_once(ctx)
    total += await _yield_once(ctx)
    return total


def test_tasks_complete_independently() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        var first = runtime.add(_yields_twice[10](context))
        var second = runtime.add(_yields_twice[20](context))

        runtime.wait()

        # Both ran to completion even though each parked twice on the way,
        # i.e. the queue really did round-robin between them.
        assert_true(first.is_completed())
        assert_true(second.is_completed())
        assert_equal(first^.wait(), 12)
        assert_equal(second^.wait(), 22)


async def _increment_twice(
    ctx: Context, counter: Pointer[Int, MutUntrackedOrigin]
):
    counter[] += 1
    await suspend(ctx)
    counter[] += 1
    await suspend(ctx)


def test_tasks_make_progress_without_corrupting_shared_state() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        # `counter` has to live behind a pointer, not as a bare local:
        # it's read and written from three coroutines reached through
        # `counter_ptr`'s untracked origin, a path the compiler can't see
        # aliases `counter` itself. Same issue as `_RuntimeInner._q` in
        # `warp/runtime.mojo`.
        var counter = OwnedPointer(0)
        var counter_ptr = counter.ptr().unsafe_origin_cast[MutUntrackedOrigin]()

        var t1 = runtime.add(_increment_twice(context, counter_ptr))
        var t2 = runtime.add(_increment_twice(context, counter_ptr))
        var t3 = runtime.add(_increment_twice(context, counter_ptr))

        runtime.wait()

        assert_true(t1.is_completed())
        assert_true(t2.is_completed())
        assert_true(t3.is_completed())

        # Every increment landed exactly once: 3 tasks x 2 increments
        # each, with no lost or duplicated update despite all three being
        # interleaved on one runtime. This only checks the outcome, not
        # which task's increment happened at which step -- the resume
        # order between tasks is an implementation detail, not a
        # contract (see this file's ground rule).
        assert_equal(counter_ptr[], 6)


async def _no_yield(value: Int) -> Int:
    return value


def test_mixed_yielding_and_non_yielding_tasks_complete_correctly() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        var t1 = runtime.add(_no_yield(10))
        var t2 = runtime.add(_yield_once(context))
        var t3 = runtime.add(_no_yield(20))
        var t4 = runtime.add(_yield_once(context))

        runtime.wait()

        assert_equal(t1^.wait(), 10)
        assert_equal(t2^.wait(), 1)
        assert_equal(t3^.wait(), 20)
        assert_equal(t4^.wait(), 1)


async def _nested_yield[n: Int](ctx: Context) -> Int:
    comptime assert n >= 0

    comptime if n == 0:
        await suspend(ctx)
        return 1
    else:
        return 1 + await _nested_yield[n - 1](ctx)


def test_nested_yielding_tasks() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        # Each task parks at the bottom of its chain, so resuming it has to
        # unwind back up through every enclosing frame. Two tasks of
        # different depths run side by side on one runtime.
        var deep = runtime.add(_nested_yield[16](context))
        var shallow = runtime.add(_nested_yield[3](context))

        runtime.wait()

        assert_true(deep.is_completed())
        assert_true(shallow.is_completed())
        assert_equal(deep^.wait(), 17)
        assert_equal(shallow^.wait(), 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
