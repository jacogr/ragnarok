# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent fixed signing bytes use literal report-hash witnesses, never a production hash.

proc expectedGuarantee*(hash: array[32, byte]): array[45, byte] =
  ## Spell the normative ASCII token as literal octets to witness exact domain framing independently.
  result = default(array[45, byte])
  const domain = [106'u8, 97, 109, 95, 103, 117, 97, 114, 97, 110, 116, 101, 101]
  # Copy the exact thirteen ASCII bytes without a dollar sign or terminator.
  for index in 0..<domain.len: result[index] = domain[index]
  # Preserve all 32 independent full-report digest octets without another hash or slot suffix.
  for index in 0..<32: result[13+index] = hash[index]
