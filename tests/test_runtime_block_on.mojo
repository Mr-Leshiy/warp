"""`Runtime.block_on`: runs a root coroutine to completion and returns its
value or re-raises its error, including a root that spawns and waits on
other tasks.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_equal, assert_raises

from warp.runtime import Runtime

from tests.common import suspend


async def _yields_twice[VALUE: Int](runtime: Runtime) -> Int:
    await suspend(runtime)
    await suspend(runtime)
    return VALUE


async def _raises_after_yield(runtime: Runtime) raises -> Int:
    await suspend(runtime)
    raise Error("root failure")


async def _spawns_and_waits(runtime: Runtime) raises -> Int:
    var spawner = runtime.copy()
    var first = spawner.add(_yields_twice[10](runtime.copy()))
    var second = spawner.add(_yields_twice[20](runtime.copy()))
    await suspend(runtime)
    return first^.wait() + second^.wait()


def test_block_on_returns_value() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var shared = runtime.copy()
        assert_equal(runtime.block_on(_yields_twice[7](shared)), 7)


def test_block_on_reraises_error() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var shared = runtime.copy()
        with assert_raises(contains="root failure"):
            _ = runtime.block_on(_raises_after_yield(shared))


def test_block_on_root_spawns_and_waits_on_other_tasks() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var shared = runtime.copy()
        assert_equal(runtime.block_on(_spawns_and_waits(shared)), 30)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
