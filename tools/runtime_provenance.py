# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Resolve runtime provenance and reject omitted verification tooling before setup.

Exposes runtime_sources and validate_coverage for complete verification input tracking.
"""
from pathlib import Path
from verification_inventory import RUNTIME_SOURCES, UNIT_SUITES
from compiler_fixtures import COMPILER_FIXTURES

ROOT = Path(__file__).resolve().parents[1]
# Historical measurement tooling is not part of the supported verification path.
EXCLUSIONS = {'tools/compare_nimony.py': 'Historical Nim 2 measurement control, not current verification.'}
# Check nested helpers too; bytecode and native build caches do not match these source extensions.
COVERAGE_PATTERNS = ('tools/**/*.py', 'tools/**/*.json', 'tests/**/*.py')


# Enforce feature/path insertion points in the remaining shared literal list rather than sorting silently.
def validate_source_order(values):
    if list(values) != sorted(values):
        # Prefix grouping follows repository-relative module paths; appending unrelated paths fails preflight.
        raise ValueError('Runtime sources must be alphabetical; insert beside the matching module/feature prefix')


# Keep explicit and discovered inputs identical between preflight and runtime evidence generation.
def runtime_sources():
    from native_tests import unit_source, unit_fixture_sources
    validate_source_order(RUNTIME_SOURCES)
    sources = [ROOT/path for path in RUNTIME_SOURCES]
    sources += sorted((ROOT/'tools/native_requirements').glob('*/*.json'))
    sources += sorted((ROOT/'tools/failure_suites').glob('*.json'))
    sources += list((ROOT/'src/codec').glob('*.nim')) + list((ROOT/'src/state').glob('*.nim'))
    sources += [unit_source(name) for name in UNIT_SUITES]
    sources += [unit_source(name).with_suffix('.output') for name in UNIT_SUITES]
    sources += unit_fixture_sources()
    sources += list((ROOT/'tests').glob('report_*.py')) + list((ROOT/'tests').glob('guarantees_*.py'))
    sources += list((ROOT/'tests/native').glob('nimony_*.nim'))
    sources += [ROOT/f'tests/native/compile_fail/{name}.nim' for name in COMPILER_FIXTURES]
    sources += [ROOT/'tools/test_runtime.py']
    return sources


# Require each tooling source to be hashed or explicitly excluded with a reviewable reason.
def validate_coverage(root, sources, exclusions=EXCLUSIONS):
    actual = {str(path.relative_to(root)) for pattern in COVERAGE_PATTERNS
              for path in root.glob(pattern) if path.is_file()}
    covered = {str(path.relative_to(root)) for path in sources}
    for name, reason in exclusions.items():
        # Stale exclusions and newly covered exceptions must be removed, not silently accumulated.
        if name not in actual or name in covered or not isinstance(reason, str) or not reason.strip():
            raise ValueError('Invalid provenance exclusion: '+name)
    missing = actual - covered - exclusions.keys()
    if missing:
        # A new source needs an inventory entry or an explicit, justified exclusion.
        raise ValueError('Unlisted runtime provenance sources: '+', '.join(sorted(missing)))
