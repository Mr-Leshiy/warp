# WARP

A single-threaded async runtime for GPU-based Mojo coroutines. It smartly
coalesces `DeviceContext.synchronize()` calls across queued tasks.

> **Warning**
> Async support in `Mojo` is experimental. APIs here may change without notice
> and should not be relied on for production use.

```mojo
from max.gpu.host import DeviceContext, HostBuffer
from max.gpu import global_idx
from std.memory import unsafe_memcpy
from warp import Context, Runtime


def square_kernel(buf: Pointer[Float32, MutAnyOrigin], size: Int32):
    var idx = global_idx.x
    if idx < Int(size):
        var value = buf[unsafe_offset=idx]
        buf[unsafe_offset=idx] = value * value


# Device calls live in a plain `def`: called directly inside an `async def`
# they crash the compiler.
def enqueue_square[
    size: Int
](ctx: Context, input: Array[Float32, size]) raises -> HostBuffer[
    DType.float32
]:
    var device_buffer = ctx.enqueue_device_buffer(input)
    ctx.gpu_ctx().enqueue_function[square_kernel](
        device_buffer, Int32(size), grid_dim=1, block_dim=size
    )
    return ctx.enqueue_host_buffer(device_buffer)


async def square[
    size: Int
](ctx: Context, input: Array[Float32, size]) raises -> Array[Float32, size]:
    var host_buffer = enqueue_square(ctx, input)
    await ctx.synchronize()

    var result = Array[Float32, size](uninitialized=True)
    unsafe_memcpy(
        dest=result.unsafe_ptr(), src=host_buffer.unsafe_ptr(), count=size
    )
    return result^


def main() raises:
    with DeviceContext() as ctx:
        var runtime = Runtime(ctx)
        var context = runtime.context()

        # Run a single coroutine to completion and get its result.
        var input1: Array[Float32, 4] = [1, 2, 3, 4]
        print(runtime.block_on(square(context, input1)))  # [1, 4, 9, 16]

        # Or queue several tasks and run them concurrently.
        var input2: Array[Float32, 4] = [5, 6, 7, 8]
        var t2 = runtime.add(square(context, input2))

        var input3: Array[Float32, 4] = [9, 10, 11, 12]
        var t3 = runtime.add(square(context, input3))

        runtime.wait()
        print(t2^.wait())  # [25, 36, 49, 64]
        print(t3^.wait())  # [81, 100, 121, 144]
```

## Install

Requires [pixi](https://pixi.sh) >=`0.78.0`.

```toml
[workspace]
channels = ["conda-forge", "https://conda.modular.com/max"]
preview = ["pixi-build"]

[dependencies]
warp = { git = "https://github.com/Mr-Leshiy/warp.git", tag = "<latest-release>" }
```

```bash
pixi install
```

Pin to a [released tag](https://github.com/Mr-Leshiy/warp/releases) for reproducible builds.

To track unreleased work (breaking changes possible between tags):

```toml
[dependencies]
warp = { git = "https://github.com/Mr-Leshiy/warp.git", branch = "main" }
```

## Development

```sh
pixi run fmt    # format
pixi run test   # run tests (needs a GPU-enabled host)
pixi run docs   # build the API docs site
```

## How it works

- `Runtime.block_on()` runs one coroutine until it completes and returns its
  result (or re-raises its error); other queued tasks only run while it's
  pending.
- `Runtime.add()` queues a task; nothing runs until `wait()`.
- `wait()` pops queued coroutines FIFO and resumes each in turn. A
  coroutine keeps running until it returns or `await`s
  `Context.synchronize()`, which hands control back to the runtime.
- Only `await ctx.synchronize()` ever needs an actual device sync, and the
  runtime fires it lazily — once, right before the first coroutine that's
  waiting on one resumes. Any other coroutine queued behind it rides that
  same sync for free instead of triggering its own.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or
[MIT license](LICENSE-MIT) at your option.
