#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Validate project-owned verification inputs without provisioning or executing native dependencies.

Exposes validate_registration, validate_inventory and a CLI that fails on missing or
inconsistent verification registrations.
"""
import ast
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


# Suite files must have exactly one explicit scheduler call; discovery never implicitly runs new probes.
def validate_registration(suites, source):
    tree = ast.parse(source)
    runner = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'run_failures')
    names = []
    for node in ast.walk(runner):
        # Only the shared suite calls participate; specialized fixture/control paths stay explicit.
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'run_failure_suite':
            if not node.args or not isinstance(node.args[-1], ast.Constant) or not isinstance(node.args[-1].value, str):
                # Require reviewable literal registration rather than computed names that hide omissions.
                raise ValueError('Failure suite registration must use a literal family name')
            names.append(node.args[-1].value)
    if len(names) != len(set(names)) or set(names) != set(suites):
        # Report both directions so a misspelling or forgotten runner call is immediately actionable.
        raise ValueError('Failure registration mismatch: missing files='+str(sorted(set(names)-set(suites)))
                         +', unscheduled files='+str(sorted(set(suites)-set(names)))
                         +', duplicate calls='+str(len(names)-len(set(names))))


# Resolve local inventories only; pinned dependency trees retain their existing setup/provenance checks.
def validate_inventory():
    from failure_checks import FAILURE_SUITES
    from native_tests import unit_source
    from native_requirements import UNIT_LINKS
    from verification_inventory import UNIT_SUITES
    from compiler_fixtures import COMPILER_FIXTURES
    from runtime_provenance import runtime_sources
    runtime_sources()
    validate_registration(FAILURE_SUITES, (ROOT/'tools/test_runtime.py').read_text())
    expected = {unit_source(name) for name in UNIT_SUITES}
    for source in expected:
        # Each positive native source requires its own checked-in output contract.
        if not source.with_suffix('.output').is_file():
            raise ValueError('Missing expected output: '+str(source.relative_to(ROOT)))
    if not all(profile in (None, 'crypto', 'observer', 'bandersnatch', 'bandersnatch_observer', 'quic')
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
