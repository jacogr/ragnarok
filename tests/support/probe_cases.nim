# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Select a typed runtime misuse case or enumerate its declared names before fixture preparation.
## Exposes selectProbe; unknown labels exit with setup status 2 rather than a guard verdict.

import std/syncio

proc selectProbe*[T: enum](label: string): T =
  ## Return the declared enum value, list all case names, or terminate on an unknown trusted label.
  mixin `$`
  if label == "--list-cases":
    # Listing precedes fixture setup so Python can verify the compiled dispatch declaration itself.
    for ordinal in ord(low(T))..ord(high(T)):
      let value = T(ordinal)
      # Custom enum strings are the stable command-line case identities.
      echo $value
    quit 0
  for ordinal in ord(low(T))..ord(high(T)):
    let value = T(ordinal)
    # Return only an explicitly declared case; typed dispatch must cover every value.
    if $value == label:
      return value
  # Unknown cases are setup failures and cannot satisfy the expected assertion diagnostic.
  quit 2
