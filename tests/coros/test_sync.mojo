"""`_spawn_synchronize_coro`: queues at most one device-sync coroutine at a
time, and clears `_has_sync_coro` once that coroutine completes.
"""

from max.gpu.host import DeviceContext
from std.testing import TestSuite, assert_equal

from warp.coros import _spawn_synchronize_coro
from warp.executor import Executor


def test_spawn_queues_a_sync_coro_and_clears_the_flag_on_completion() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)

        _spawn_synchronize_coro(executor._inner)
        assert_equal(executor._inner[]._has_sync_coro[], True)
        assert_equal(len(executor._inner[]._q[]), 1)

        executor.wait()
        assert_equal(executor._inner[]._has_sync_coro[], False)
        assert_equal(len(executor._inner[]._q[]), 0)


def test_spawn_does_not_queue_a_second_sync_coro_while_one_is_pending() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)

        _spawn_synchronize_coro(executor._inner)
        _spawn_synchronize_coro(executor._inner)
        assert_equal(len(executor._inner[]._q[]), 1)

        executor.wait()
        assert_equal(executor._inner[]._has_sync_coro[], False)

        # Once the first one completed, a new request spawns a fresh one.
        _spawn_synchronize_coro(executor._inner)
        assert_equal(executor._inner[]._has_sync_coro[], True)
        assert_equal(len(executor._inner[]._q[]), 1)

        executor.wait()
        assert_equal(executor._inner[]._has_sync_coro[], False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
