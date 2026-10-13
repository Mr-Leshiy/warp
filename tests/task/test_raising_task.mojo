"""`RaisingTask`: error propagation from a coroutine that raises
immediately, after suspending, or from a nested coroutine.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_raises

from warp.runtime import Runtime

from tests.common import suspend


__async def _raises_immediately() raises -> Int:
    raise Error("immediate failure")


def test_raising_task_raises_immediately() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var task = runtime.add(_raises_immediately())
        with assert_raises(contains="immediate failure"):
            _ = task^.wait()


__async def _raises_after_yields(runtime: Runtime) raises -> Int:
    __await suspend(runtime)
    __await suspend(runtime)
    raise Error("failure after yields")


def test_raising_task_raises_after_yields() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var shared = runtime.copy()
        var task = runtime.add(_raises_after_yields(shared))
        with assert_raises(contains="failure after yields"):
            _ = task^.wait()


__async def _raises_from_nested_coroutine(runtime: Runtime) raises -> Int:
    # TODO: remove `@no_inline` once
    # https://github.com/modular/modular/issues/7257 is resolved.
    @no_inline
    __async def _raises_inner(runtime: Runtime) raises -> Int:
        __await suspend(runtime)
        raise Error("nested failure")

    return __await _raises_inner(runtime)


def test_raising_task_raises_from_nested_coroutine() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var shared = runtime.copy()
        var task = runtime.add(_raises_from_nested_coroutine(shared))
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
        var shared = runtime.copy()
        var task = runtime.add(_raises_after_yields(shared))

        runtime.wait()
        with assert_raises(contains="failure after yields"):
            _ = task^.wait()


def test_raising_task_runtime_wait_raises_from_nested_coroutine() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var shared = runtime.copy()
        var task = runtime.add(_raises_from_nested_coroutine(shared))

        runtime.wait()
        with assert_raises(contains="nested failure"):
            _ = task^.wait()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
