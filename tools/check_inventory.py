#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate project-owned verification inputs without provisioning or executing native dependencies.

Exposes validate_inventory and a CLI that fails on missing or
inconsistent verification declarations.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


# Match the workflow's explicit family matrix against the source-owned plan before provisioning.
def validate_e2e_groups(workflow):
    """Reject missing, duplicate or unknown CI families without constraining job presentation."""
    from e2e_checks import PLAN
    from test_mcp_interop import CI_GROUP
    section = re.search(r'^  e2e:\n(.*?)(?=^  [\w-]+:|\Z)', workflow, re.MULTILINE | re.DOTALL)
    groups = () if section is None else tuple(re.findall(
        r'^\s*-\s*\{group:\s*([a-z_]+)(?:,|\})', section[1], re.MULTILINE))
    # The official SDK driver owns its isolated dependencies and evidence outside the native plan.
    expected = set((*PLAN.groups(), CI_GROUP))
    if set(groups) != expected or len(groups) != len(expected):
        raise ValueError('E2E matrix must contain each declared group once')


# Resolve local inventories only; pinned dependency trees retain their existing setup/provenance checks.
def validate_inventory():
    from failure_checks import FAILURE_SUITES
    from native_tests import unit_source
    from native_requirements import UNIT_LINKS
    from verification_inventory import UNIT_SUITES, ARC_SUITES
    from failure_plans import FAILURE_COUNTS
    from compiler_fixtures import COMPILER_FIXTURES
    from runtime_provenance import runtime_sources
    from test_models import declarations
    collisions = set(ARC_SUITES.values()).intersection(FAILURE_COUNTS)
    if collisions:
        # Unit ARC observations must not masquerade as foreign runtime-contract results.
        raise ValueError('ARC report keys overlap runtime failure families: '+', '.join(sorted(collisions)))
    from pvm_sanitizers import validate_profiles
    validate_profiles()
    runtime_sources()
    declarations(ROOT/'tests/models')
    validate_e2e_groups((ROOT/'.github/workflows/ci.yml').read_text())
    expected = {unit_source(name) for name in UNIT_SUITES}
    for source in expected:
        # Each positive native source requires its own checked-in output contract.
        if not source.with_suffix('.output').is_file():
            raise ValueError('Missing expected output: '+str(source.relative_to(ROOT)))
    if not all(profile in (None, 'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic', 'storage_io', 'polkavm')
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
