# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Discover source-marked typed runtime failure drivers and check compiled mode enumeration.

Exposes load_failure_drivers, SPECIAL_DRIVERS, driver_modes and check_driver_modes.
Expected cases always come from declarations, never successful child-process observations.
"""
import json
import re
from pathlib import Path
from verification_inventory import source_metadata

ROOT = Path(__file__).resolve().parents[1]


# Read the deliberately bounded typed enum declaration, never infer tests from emitted results.
def driver_modes(source):
    """Return stable mode strings; reject absent/malformed declarations and duplicate names or labels."""
    text = Path(source).read_text()
    marker = '# @@ProbeCases\ntype VerificationProbe = enum\n'
    if text.count(marker) != 1:
        raise ValueError('Expected one typed probe declaration: '+str(source))
    block = text.split(marker)[1].split('\n\n', 1)[0]
    modes, identifiers = [], set()
    for line in block.splitlines():
        # Keep this machine-readable subset strict; Nimony separately checks exhaustive typed dispatch.
        match = re.fullmatch(r'  ([a-zA-Z][a-zA-Z0-9]*) = ("[a-z0-9-]+")', line)
        if match is None:
            raise ValueError('Invalid typed probe case: '+str(source)+' '+line)
        label = json.loads(match[2])
        if match[1] in identifiers or label in modes:
            raise ValueError('Duplicate typed probe case: '+label)
        identifiers.add(match[1])
        modes.append(label)
    if not modes or modes != sorted(modes):
        raise ValueError('Typed probe cases must be nonempty and alphabetical: '+str(source))
    return tuple(modes)


# Discover marked top-level probes; typed modes and source headers must agree on driver ownership.
def load_failure_drivers(folder):
    """Return family-to-source mappings without a separate list of driver filenames."""
    drivers = {}
    for source in sorted(Path(folder).glob('*.nim')):
        # A typed probe cannot quietly disappear when its header is removed or renamed.
        metadata = source_metadata(source)
        typed = '# @@ProbeCases' in source.read_text().splitlines()
        if not metadata and not typed:
            continue
        if metadata != {'group': 'failure_driver'}:
            raise ValueError('Invalid or missing failure driver declaration: '+str(source))
        match = re.fullmatch(r'nimony_([a-z][a-z0-9_]*)_results', source.stem)
        if match is None or match[1] in drivers:
            raise ValueError('Invalid or duplicate failure driver identity: '+str(source))
        driver_modes(source)
        drivers[match[1]] = source
    return drivers


# Discovery owns identities; specialized handlers independently require exact declared-driver coverage.
SPECIAL_DRIVERS = load_failure_drivers(ROOT/'tests/native')


# A compiled driver's enumeration must match its pre-execution source declaration exactly.
def check_driver_modes(command, binary, family, report):
    result = command([binary, '--list-cases'], family+'-declared-cases')
    passed = result['exit_code'] == 0 and result['output'].splitlines() == list(driver_modes(SPECIAL_DRIVERS[family]))
    report.setdefault('probe_cases', {})[family] = dict(passed=passed, check=result)
