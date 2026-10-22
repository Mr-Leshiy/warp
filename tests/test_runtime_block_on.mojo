"""`Runtime.block_on`: runs a root coroutine to completion and returns its
value or re-raises its error, including a root that spawns and waits on
other tasks.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_equal, assert_raises

from warp.context import Context
from warp.runtime import Runtime

from tests.common import suspend


__async def _yields_twice[VALUE: Int](ctx: Context) -> Int:
    __await suspend(ctx)
    __await suspend(ctx)
    return VALUE


__async def _raises_after_yield(ctx: Context) raises -> Int:
    __await suspend(ctx)
    raise Error("root failure")


__async def _spawns_and_waits(runtime: Runtime, ctx: Context) raises -> Int:
    var spawner = runtime.copy()
    var first = spawner.add(_yields_twice[10](ctx))
    var second = spawner.add(_yields_twice[20](ctx))
    __await suspend(ctx)
    return first^.wait() + second^.wait()


def test_block_on_returns_value() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        assert_equal(runtime.block_on(_yields_twice[7](context)), 7)


def test_block_on_reraises_error() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        with assert_raises(contains="root failure"):
            _ = runtime.block_on(_raises_after_yield(context))


def test_block_on_root_spawns_and_waits_on_other_tasks() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var spawner = runtime.copy()
        var context = runtime.context()
        assert_equal(runtime.block_on(_spawns_and_waits(spawner, context)), 30)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
