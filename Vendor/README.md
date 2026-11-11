# MLX compatibility patch

`mlx-swift/` contains mlx-swift 0.30.2 source (revision `f58bd2c2b3b84316da69182f436db4219aff30b9`) (licenses retained), the exact version required by Kokoro. Device and Mac harness projects use this local package so the fix survives dependency resolution and clean builds.

`Source/Cmlx/mlx/mlx/backend/metal/device.h`: `set_vector_bytes` supplies a zero-initialized element for empty vectors, backported from https://github.com/ml-explore/mlx/pull/4622 (merged October 5, 2026; merge 08298bb). This version uses `enc_` instead of the newer `get_command_encoder()` accessor. Index counts remain zero, so kernels do not read the placeholder.

Metal validation stays enabled. Remove this local override when Kokoro supports an MLX release containing the fix.

## iOS background submission gate (Bookreader-specific)

`Source/Cmlx/mlx/mlx/backend/metal/device.cpp` adds a mutex/condition-variable gate around command-buffer submission. `GPU.setSubmissionAllowed` exposes it through `Source/MLX/GPU+Metal.swift` and `Source/Cmlx/include/mlx/c/metal.h`. This is a local lifecycle integration, not an upstream patch.

When managed, each submission waits until scheduled while holding the gate. Closing the gate therefore prevents new commits and ensures earlier submissions are scheduled, as required by [Apple's Metal background guidance](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background). It does not wait for an entire Kokoro inference on the main thread. Inference workers with unsent buffers wait until foreground or an actual GPU grant returns; buffers are never discarded and errors are not suppressed.

The app installs synchronous UIKit notification observers before its first scene. Grant/expiration state is serialized and an expired grant cannot be resurrected by a late callback. The host harness verifies that GPU evaluation waits while closed and produces the expected values after reopening; real screen-lock and grant-expiration behavior still requires iPhone validation.
