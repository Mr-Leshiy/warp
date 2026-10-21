"""`RaisingTask`: error propagation from a coroutine that raises
immediately, after suspending, or from a nested coroutine.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_raises

from warp.context import Context
from warp.runtime import Runtime

from tests.common import suspend


async def _raises_immediately() raises -> Int:
    raise Error("immediate failure")


def test_raising_task_raises_immediately() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var task = runtime.add(_raises_immediately())
        with assert_raises(contains="immediate failure"):
            _ = task^.wait()


async def _raises_after_yields(ctx: Context) raises -> Int:
    await suspend(ctx)
    await suspend(ctx)
    raise Error("failure after yields")


def test_raising_task_raises_after_yields() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var task = runtime.add(_raises_after_yields(context))
        with assert_raises(contains="failure after yields"):
            _ = task^.wait()


async def _raises_from_nested_coroutine(ctx: Context) raises -> Int:
    # TODO: remove `@no_inline` once
    # https://github.com/modular/modular/issues/7257 is resolved.
    @no_inline
    async def _raises_inner(ctx: Context) raises -> Int:
        await suspend(ctx)
        raise Error("nested failure")

    return await _raises_inner(ctx)


def test_raising_task_raises_from_nested_coroutine() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var task = runtime.add(_raises_from_nested_coroutine(context))
        with assert_raises(contains="nested failure"):
            _ = task^.wait()


def test_raising_task_runtime_wait_raises_immediately() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var task = runtime.add(_raises_immediately())

        runtime.wait()
        with assert_raises(contains="immediate failure"):
            _ = task^.wait()


def test_raising_task_runtime_wait_raises_after_yields() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var task = runtime.add(_raises_after_yields(context))

        runtime.wait()
        with assert_raises(contains="failure after yields"):
            _ = task^.wait()


def test_raising_task_runtime_wait_raises_from_nested_coroutine() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()
        var task = runtime.add(_raises_from_nested_coroutine(context))

        runtime.wait()
        with assert_raises(contains="nested failure"):
            _ = task^.wait()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
