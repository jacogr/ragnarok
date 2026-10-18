# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default native results cannot be retagged as success.
import ../../../src/bandersnatch/bandersnatch
var parsed = default(BsResult[BsKey])
parsed.status = BsError.None
