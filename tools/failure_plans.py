# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Declare expected runtime case plans before execution, using family data and typed driver cases.

Exposes FAILURE_PLANS, derived FAILURE_COUNTS, SPECIAL_CASES and driver_modes. Expected identities
never come from observed successful results; normal case metadata remains in existing family files.
"""
import json
import re
from pathlib import Path
from failure_checks import FAILURE_SUITES

ROOT = Path(__file__).resolve().parents[1]
SPECIAL_DRIVERS = {family: ROOT/f'tests/native/nimony_{family}_results.nim'
                   for family in ('availability', 'bandersnatch', 'composition', 'workqueues')}


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


# Resource/variant combinations belong beside the specialized orchestration rather than a global total.
SPECIAL_CASES = {
    'store': [(member, origin, 'outcome.status == None')
              for member in ('store', 'snapshot', 'lookup') for origin in ('default', 'error')]
             + [('fork', 'default', 'outcome.status == None'),
                ('metadata', 'default', 'not snapshot.data == nil'),
                ('length', 'default', 'not view.owner.data == nil'),
                ('bytes', 'default', 'not view.owner.data == nil')],
    'runtime': [('assertion', 'trial assertion sentinel', 1), ('bounds', '[AssertionDefect]', 1),
                ('wrapping', '-9223372036854775808', 0)],
    'offload': [(enabled, origin) for enabled in (False, True) for origin in ('default', 'empty')],
}
for family, source in SPECIAL_DRIVERS.items():
    # Default/error access uses the same declared mode set as the compiled driver's dispatch.
    modes = driver_modes(source)
    ordinary = [mode for mode in modes if not (family == 'availability' and mode.startswith('absent-'))]
    SPECIAL_CASES[family] = [(mode, origin, 'value.status == None')
                             for origin in ('default', 'error') for mode in ordinary]
    if family == 'availability':
        # Inactive assignment fields retain default, explicitly absent and decoded-absence origins.
        SPECIAL_CASES[family] += [(mode, origin, 'assignment.isPresent')
                                  for origin in ('default', 'source', 'decoded')
                                  for mode in modes if mode.startswith('absent-')]

FAILURE_PLANS = {family: [case['identity'] for case in suite['cases']]
                 for family, suite in FAILURE_SUITES.items()}
for family, cases in SPECIAL_CASES.items():
    # Plans describe expected identities before any child process starts, including language-policy controls.
    if family == 'runtime':
        identities = [dict(name=mode) for mode, _, _ in cases]
    elif family == 'offload':
        identities = [dict(enabled=enabled, origin=origin) for enabled, origin in cases]
    else:
        identities = [dict(member=member, origin=origin) for member, origin, _ in cases]
    if family in FAILURE_PLANS:
        raise ValueError('Duplicate runtime failure family: '+family)
    FAILURE_PLANS[family] = identities
FAILURE_PLANS = dict(sorted(FAILURE_PLANS.items()))
# Summaries may retain derived totals; no separately maintained counts participate in registration.
FAILURE_COUNTS = {family: len(cases) for family, cases in FAILURE_PLANS.items()}


# A compiled driver's enumeration must match its pre-execution source declaration exactly.
def check_driver_modes(command, binary, family, report):
    result = command([binary, '--list-cases'], family+'-declared-cases')
    passed = result['exit_code'] == 0 and result['output'].splitlines() == list(driver_modes(SPECIAL_DRIVERS[family]))
    report.setdefault('probe_cases', {})[family] = dict(passed=passed, check=result)
