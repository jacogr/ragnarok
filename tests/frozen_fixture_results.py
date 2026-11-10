# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare independent result fields separately from preflight-owned fixture links."""
from copy import deepcopy
from functools import lru_cache
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from fixture_link_paths import locate

FIXTURES = Path(__file__).resolve().parent/'fixtures'


@lru_cache(maxsize=1)
def links():
    """Load the checked-in link declarations for this test invocation."""
    return json.loads((FIXTURES/'fixture-evidence-links.json').read_text())


def result_fields(record, fields):
    """Project out only the declared raw-file digest fields, including list members."""
    if not fields:
        return record
    result = deepcopy(record)
    for field in fields:
        location = locate(result, field)
        if location:
            parent, key = location
            del parent[key]
    return result


def matches_frozen_results(fixture, evidence, *, fields=None):
    """Compare exact behavioral evidence for the whole record or selected result fields."""
    frozen = json.loads(fixture.read_text())
    declared = links().get(fixture.resolve().relative_to(FIXTURES).as_posix(), {})
    if fields is not None:
        frozen = {name: frozen[name] for name in fields}
    return result_fields(frozen, declared) == result_fields(evidence, declared)
