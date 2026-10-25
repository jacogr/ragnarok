# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reuse successful independent derivation for one fixed source tree while returning caller-owned histories."""
from copy import deepcopy
from functools import lru_cache,wraps


def owned_histories(factory):
    """Cache one no-argument GP history factory privately; failures are not cached and every caller receives a deep copy."""
    @lru_cache(maxsize=1)
    def frozen():
        """Derive from pinned source inputs only; native results never enter this cache."""
        return factory()
    @wraps(factory)
    def owned():
        """Do not expose cached mutable maps, steps, events or inventories to a caller."""
        return deepcopy(frozen())
    return owned
