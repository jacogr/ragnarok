# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Expose shuffled() for reproducible per-run plans without timing weights or maintained assignments."""
import random


# A fresh private generator gives every runner the same plan, independent of other random users.
def shuffled(items, seed, group):
    values = list(items)
    if seed is not None:
        # Reject malformed report seeds instead of silently validating another partition's scope.
        if not isinstance(seed, str) or not seed.strip():
            raise ValueError('Shard seed must be a nonempty string')
        random.Random(group+':'+seed).shuffle(values)
    return values
