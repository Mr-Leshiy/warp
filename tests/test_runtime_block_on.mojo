"""`Runtime.block_on`: runs a root coroutine to completion and returns its
value or re-raises its error, including a root that spawns and waits on
other tasks.
"""

from std.sys.info import CompilationTarget
from std.testing import TestSuite, assert_equal, assert_raises

from warp.context import Context
from warp.runtime import Runtime
from warp.task import Task

from tests.common import CpuDeviceContext, suspend


__async def _yields_twice[VALUE: Int](ctx: Context) -> Int:
    __await suspend(ctx)
    __await suspend(ctx)
    return VALUE


__async def _raises_after_yield(ctx: Context) raises -> Int:
    __await suspend(ctx)
    raise Error("root failure")


__async def _waits_on_others[
    origins1: OriginSet, origins2: OriginSet, target: CompilationTarget
](
    ctx: Context[target],
    var first: Task[Int, origins1, target],
    var second: Task[Int, origins2, target],
) raises -> Int:
    __await suspend(ctx)
    return first^.wait() + second^.wait()


def test_block_on_returns_value() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        assert_equal(runtime.block_on(_yields_twice[7](context)), 7)


def test_block_on_reraises_error() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        with assert_raises(contains="root failure"):
            _ = runtime.block_on(_raises_after_yield(context))


def test_block_on_root_spawns_and_waits_on_other_tasks() raises:
    with CpuDeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var first = runtime.add(_yields_twice[10](context))
        var second = runtime.add(_yields_twice[20](context))
        assert_equal(
            runtime.block_on(_waits_on_others(context, first^, second^)), 30
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
