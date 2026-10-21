#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate project-owned verification inputs without provisioning or executing native dependencies.

Exposes validate_inventory and a CLI that fails on missing or
inconsistent verification declarations.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


# Resolve local inventories only; pinned dependency trees retain their existing setup/provenance checks.
def validate_inventory():
    from failure_checks import FAILURE_SUITES
    from native_tests import unit_source
    from native_requirements import UNIT_LINKS
    from verification_inventory import UNIT_SUITES, ARC_SUITES
    from failure_plans import FAILURE_COUNTS
    from compiler_fixtures import COMPILER_FIXTURES
    from runtime_provenance import runtime_sources
    collisions = set(ARC_SUITES.values()).intersection(FAILURE_COUNTS)
    if collisions:
        # Unit ARC observations must not masquerade as foreign runtime-contract results.
        raise ValueError('ARC report keys overlap runtime failure families: '+', '.join(sorted(collisions)))
    runtime_sources()
    expected = {unit_source(name) for name in UNIT_SUITES}
    for source in expected:
        # Each positive native source requires its own checked-in output contract.
        if not source.with_suffix('.output').is_file():
            raise ValueError('Missing expected output: '+str(source.relative_to(ROOT)))
    if not all(profile in (None, 'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic', 'storage_io')
               for profile in UNIT_LINKS.values()):
        # Reject names for which native setup cannot supply a prepared library.
        raise ValueError('Unknown native unit linking profile')
    return len(FAILURE_SUITES), sum(len(suite['cases']) for suite in FAILURE_SUITES.values()), len(expected)


# Print one concise failure before any setup work; this command intentionally requires only Python.
def main():
    try:
        families, probes, native = validate_inventory()
    except (ValueError, KeyError, TypeError, OSError, SyntaxError, StopIteration) as error:
        # Validation failures remain a nonzero command, including malformed JSON or scheduler source.
        print('FAIL verification inventory: '+str(error), file=sys.stderr)
        return 1
    print(f'PASS verification inventory: {families} failure families, {probes} data-driven probes, {native} native suites')
    return 0


# Importing the validator exposes pure checks without starting verification or dependency setup.
if __name__ == '__main__':
    raise SystemExit(main())
