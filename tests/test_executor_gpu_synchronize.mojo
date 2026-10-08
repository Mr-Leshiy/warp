from max.gpu.host import DeviceBuffer, DeviceContext, HostBuffer
from max.gpu import global_idx
from std.testing import TestSuite, assert_equal

from warp.context import Context
from warp.executor import Executor


# Iterations of busy work in `square_kernel`.
comptime BUSY_ITERATIONS = Int32(1 << 24)


# Workaround for a nightly compiler crash: `enqueue_copy`/`enqueue_function`
# called directly inside an `async def` body crash the compiler, so all the
# device calls are made from this plain `def` instead.
def _enqueue_square[
    size: Int
](ctx: Context, src: Pointer[Float32, ImmutAnyOrigin]) raises -> HostBuffer[
    DType.float32
]:
    """Enqueue the copy in, `square_kernel` and the copy out, without waiting.

    Returns both buffers so the caller keeps them alive until the queued work
    is done; the result is in the `HostBuffer` once the device is synced.
    """

    def square_kernel(buf: Pointer[Float32, MutAnyOrigin], iterations: Int32):
        var idx = global_idx.x

        var value = buf[unsafe_offset=idx]

        # Busy work so the kernel takes significant time. Kept from being
        # optimized away: the iteration count is a runtime argument, the
        # state is seeded from runtime data, xorshift has no closed form to
        # collapse the loop into, and the result feeds a branch the compiler
        # can't prove dead.
        var state = UInt32(idx) ^ value.to_bits[DType.uint32]() ^ 0x9E3779B9
        for _ in range(iterations):
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
        if state == 0:
            # Unreachable: xorshift never maps a nonzero state to zero.
            value = 0

        buf[unsafe_offset=idx] = value * value

    var device_buffer = ctx.gpu_ctx().enqueue_create_buffer[DType.float32](size)
    var host_buffer = ctx.gpu_ctx().enqueue_create_host_buffer[DType.float32](
        size
    )
    ctx.gpu_ctx().enqueue_copy(dst_buf=device_buffer, src_ptr=src)
    ctx.gpu_ctx().enqueue_function[square_kernel](
        device_buffer, BUSY_ITERATIONS, grid_dim=1, block_dim=size
    )
    # `host_buffer` is pinned, so this copy really is asynchronous: it
    # returns before the kernel finishes. A copy into pageable host memory
    # (a raw pointer into an `Array`) blocks until the data lands, which
    # would make the `await ctx.synchronize()` in `square` dead weight.
    ctx.gpu_ctx().enqueue_copy(dst_buf=host_buffer, src_buf=device_buffer)
    return host_buffer^


# `square` is a stand-in kernel: any real device work would do.
async def square[
    array_size: Int
](ctx: Context, input: Array[Float32, array_size]) raises -> Array[
    Float32, array_size
]:
    var buffer = _enqueue_square[array_size](
        ctx, input.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin]()
    )
    await ctx.synchronize()

    var result = Array[Float32, array_size](uninitialized=True)
    for i in range(array_size):
        result[i] = buffer[i]
    return result^


def test_synchronize_completes_a_real_device_round_trip() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var context = executor.context()

        var input: Array[Float32, 8] = [1, 2, 3, 4, 5, 6, 7, 8]

        var t = executor.add(square(context, input))
        assert_equal(t^.wait(), [1, 4, 9, 16, 25, 36, 49, 64])

        assert_equal(executor._inner[]._has_sync_coro[], False)


def test_synchronize_scales_to_many_concurrent_gpu_tasks() raises:
    with DeviceContext() as ctx:
        var executor = Executor(ctx)
        var context = executor.context()

        comptime ARRAY_SIZE = 8

        # `Task` is immovable (see `warp/task.mojo`): the coroutine
        # writes its result and completion flag through raw pointers
        # into the `Task` struct's own memory, so a `Task` can't be
        # moved into a `List` once created. Sixteen separately-named
        # locals is the straightforward way to hold that many of them
        # alive at once. All sixteen are queued -- none driven -- before
        # the single `executor.wait()` below, so they really do run
        # concurrently on one executor rather than one at a time.
        var input = Array[Float32, ARRAY_SIZE](fill=3)

        var t1 = executor.add(square[ARRAY_SIZE](context, input))
        var t2 = executor.add(square[ARRAY_SIZE](context, input))
        var t3 = executor.add(square[ARRAY_SIZE](context, input))
        var t4 = executor.add(square[ARRAY_SIZE](context, input))
        var t5 = executor.add(square[ARRAY_SIZE](context, input))
        var t6 = executor.add(square[ARRAY_SIZE](context, input))
        var t7 = executor.add(square[ARRAY_SIZE](context, input))
        var t8 = executor.add(square[ARRAY_SIZE](context, input))
        var t9 = executor.add(square[ARRAY_SIZE](context, input))
        var t10 = executor.add(square[ARRAY_SIZE](context, input))
        var t11 = executor.add(square[ARRAY_SIZE](context, input))
        var t12 = executor.add(square[ARRAY_SIZE](context, input))
        var t13 = executor.add(square[ARRAY_SIZE](context, input))
        var t14 = executor.add(square[ARRAY_SIZE](context, input))
        var t15 = executor.add(square[ARRAY_SIZE](context, input))
        var t16 = executor.add(square[ARRAY_SIZE](context, input))

        executor.wait()

        var expected = Array[Float32, ARRAY_SIZE](fill=9)
        assert_equal(t1^.wait(), expected)
        assert_equal(t2^.wait(), expected)
        assert_equal(t3^.wait(), expected)
        assert_equal(t4^.wait(), expected)
        assert_equal(t5^.wait(), expected)
        assert_equal(t6^.wait(), expected)
        assert_equal(t7^.wait(), expected)
        assert_equal(t8^.wait(), expected)
        assert_equal(t9^.wait(), expected)
        assert_equal(t10^.wait(), expected)
        assert_equal(t11^.wait(), expected)
        assert_equal(t12^.wait(), expected)
        assert_equal(t13^.wait(), expected)
        assert_equal(t14^.wait(), expected)
        assert_equal(t15^.wait(), expected)
        assert_equal(t16^.wait(), expected)

        assert_equal(executor._inner[]._has_sync_coro[], False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
