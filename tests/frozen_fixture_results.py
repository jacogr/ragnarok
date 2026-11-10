# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare independent result fields separately from preflight-owned fixture links."""
from functools import lru_cache
import json
from pathlib import Path

FIXTURES = Path(__file__).resolve().parent/'fixtures'


@lru_cache(maxsize=1)
def links():
    """Load the checked-in link declarations for this test invocation."""
    return json.loads((FIXTURES/'fixture-evidence-links.json').read_text())


def result_fields(record, fields):
    """Project out only the declared raw-file digest fields, including list members."""
    result = dict(record)
    for field in fields:
        container, _, key = field.partition('.')
        if not key:
            result.pop(container, None)
        elif isinstance(result.get(container), list):
            index, _, member = key.partition('.')
            if index.isdecimal() and int(index) < len(result[container]):
                rows = list(result[container])
                if isinstance(rows[int(index)], dict):
                    rows[int(index)] = dict(rows[int(index)])
                    rows[int(index)].pop(member, None)
                result[container] = rows
    return result


def matches_frozen_results(fixture, evidence, *, fields=None):
    """Compare exact behavioral evidence for the whole record or selected result fields."""
    frozen = json.loads(fixture.read_text())
    declared = links().get(fixture.resolve().relative_to(FIXTURES).as_posix(), {})
    if fields is not None:
        frozen = {name: frozen[name] for name in fields}
    return result_fields(frozen, declared) == result_fields(evidence, declared)
