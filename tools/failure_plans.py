# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Declare expected runtime case plans before execution, using family data and typed driver cases.

Exposes FAILURE_PLANS, derived FAILURE_COUNTS, SPECIAL_CASES and driver_modes. Expected identities
never come from observed successful results; normal case metadata remains in existing family files.
"""
from failure_checks import FAILURE_SUITES
from ci_shards import shuffled
from failure_drivers import SPECIAL_DRIVERS, driver_modes, check_driver_modes
from failure_controls import CONTROLS

# Keep the existing public plan view while the handlers own all specialized case declarations.
SPECIAL_CASES = {name: list(control.cases) for name, control in CONTROLS.controls.items()}

FAILURE_PLANS = {family: [case['identity'] for case in suite['cases']]
                 for family, suite in FAILURE_SUITES.items()}
for family, control in CONTROLS.controls.items():
    # Specialized handlers cannot overwrite ordinary discovered families or infer identities from successes.
    if family in FAILURE_PLANS:
        raise ValueError('Duplicate runtime failure family: '+family)
    FAILURE_PLANS[family] = control.identities()
FAILURE_PLANS = dict(sorted(FAILURE_PLANS.items()))
# Summaries may retain derived totals; no separately maintained counts participate in registration.
FAILURE_COUNTS = {family: len(cases) for family, cases in FAILURE_PLANS.items()}


# Partition ordinary families and the specialized bundle once, preserving dependency order within each.
def failure_partition(shard=None, seed=None):
    if shard is None:
        # The default local command retains the complete historical workload and verdict.
        return FAILURE_PLANS, True
    if (not isinstance(shard, (tuple, list)) or len(shard) != 2
            or any(type(value) is not int for value in shard)
            or not 1 <= shard[0] <= shard[1] <= 6):
        # Invalid subsets cannot silently become successful partial verification.
        raise ValueError('Failure shard must be index/count with 1 <= index <= count <= 6')
    index, count = shard
    if seed is not None:
        # Specialized controls form one dependent bundle whose owning shard also changes each run.
        work = shuffled([*FAILURE_SUITES, None], seed, 'failures')[index-1::count]
        families = set(work)-{None}
        specialized = None in work
    else:
        # Existing unseeded local reproductions retain their historical partition assignment.
        families = set(tuple(FAILURE_SUITES)[index-1::count])
        specialized = index == count
    plans = {family: cases for family, cases in FAILURE_PLANS.items()
             if family in families or (specialized and family in SPECIAL_CASES)}
    return plans, specialized


# Parse the bounded source-derived partition used by CI and retained verification reports.
def parse_failure_shard(value):
    shard = tuple(int(part) for part in value.split('/'))
    failure_partition(shard)
    return shard


# Ordinary shards prepare only declared native dependencies; the specialized owner retains full setup.
def failure_libraries(shard=None, seed=None):
    plans, specialized = failure_partition(shard, seed)
    if specialized:
        return None
    required = set()
    for family in plans:
        # Ordered linking remains in the family; preparation needs only the union of its provider names.
        suite = FAILURE_SUITES[family]
        required.update(suite.get('native_libraries', ()))
        for field in ('crypto_library', 'quic_library'):
            if suite.get(field) is not None:
                required.add(suite[field])
    return required
