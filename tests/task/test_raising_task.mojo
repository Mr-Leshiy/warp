"""`RaisingTask`: error propagation from a coroutine that raises
immediately, after suspending, or from a nested coroutine.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_raises

from warp.executor import Executor

from tests.common import suspend


async def _raises_immediately() raises -> Int:
    raise Error("immediate failure")


def test_raising_task_raises_immediately() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var task = executor.add(_raises_immediately())
        with assert_raises(contains="immediate failure"):
            _ = task^.wait()


async def _raises_after_yields(executor: Executor) raises -> Int:
    await suspend(executor)
    await suspend(executor)
    raise Error("failure after yields")


def test_raising_task_raises_after_yields() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var shared = executor.copy()
        var task = executor.add(_raises_after_yields(shared))
        with assert_raises(contains="failure after yields"):
            _ = task^.wait()


async def _raises_from_nested_coroutine(executor: Executor) raises -> Int:
    # TODO: remove `@no_inline` once
    # https://github.com/modular/modular/issues/7257 is resolved.
    @no_inline
    async def _raises_inner(executor: Executor) raises -> Int:
        await suspend(executor)
        raise Error("nested failure")

    return await _raises_inner(executor)


def test_raising_task_raises_from_nested_coroutine() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var shared = executor.copy()
        var task = executor.add(_raises_from_nested_coroutine(shared))
        with assert_raises(contains="nested failure"):
            _ = task^.wait()


def test_raising_task_executor_wait_raises_immediately() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var task = executor.add(_raises_immediately())

        executor.wait()
        with assert_raises(contains="immediate failure"):
            _ = task^.wait()


def test_raising_task_executor_wait_raises_after_yields() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var shared = executor.copy()
        var task = executor.add(_raises_after_yields(shared))

        executor.wait()
        with assert_raises(contains="failure after yields"):
            _ = task^.wait()


def test_raising_task_executor_wait_raises_from_nested_coroutine() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var shared = executor.copy()
        var task = executor.add(_raises_from_nested_coroutine(shared))

        executor.wait()
        with assert_raises(contains="nested failure"):
            _ = task^.wait()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
