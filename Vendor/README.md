# MLX compatibility patch

`mlx-swift/` contains mlx-swift 0.30.2 source (revision `f58bd2c2b3b84316da69182f436db4219aff30b9`) (licenses retained), the exact version required by Kokoro. Device and Mac harness projects use this local package so the fix survives dependency resolution and clean builds.

Only `Source/Cmlx/mlx/mlx/backend/metal/device.h` differs: `set_vector_bytes` supplies a zero-initialized element for empty vectors, backported from https://github.com/ml-explore/mlx/pull/4622 (merged October 5, 2026; merge 08298bb). This version uses `enc_` instead of the newer `get_command_encoder()` accessor. Index counts remain zero, so kernels do not read the placeholder.

Metal validation stays enabled. Remove this local override when Kokoro supports an MLX release containing the fix.
