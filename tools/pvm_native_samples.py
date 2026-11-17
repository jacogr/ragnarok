# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Validate copied per-invocation native counters independently of clocks and compiler readiness.

Publication and activity counters are cumulative within one immutable prepared owner. Code bytes
are current occupancy and may decrease on retirement. No counter grants executable authority.
"""

NATIVE_SAMPLE_FIELDS = ('fragments', 'calls', 'operations', 'code_bytes', 'branches', 'headers')
CUMULATIVE_FIELDS = tuple(key for key in NATIVE_SAMPLE_FIELDS if key != 'code_bytes')
MEASURED_NATIVE_SAMPLES = (0, *range(3, 13))


def validate_native_sample_log(observation, role):
    """Require thirteen ordered, bounded snapshots; interpreted execution must have no native work."""
    if (role not in ('interpreted', 'jit') or not isinstance(observation, dict)
            or set(observation) != {'samples'} or not isinstance(observation['samples'], list)
            or len(observation['samples']) != 13):
        raise ValueError('Incomplete native invocation observations')
    previous = dict.fromkeys(CUMULATIVE_FIELDS, 0)
    for index, row in enumerate(observation['samples']):
        # Occupancy is deliberately excluded from monotonic counters; valid retirement can shrink it.
        if (not isinstance(row, dict) or set(row) != {'sample', *NATIVE_SAMPLE_FIELDS}
                or any(type(value) is not int or not 0 <= value < 1 << 63
                       for value in row.values()) or row['sample'] != index):
            raise ValueError('Malformed or unordered native invocation observation')
        if any(row[key] < previous[key] for key in CUMULATIVE_FIELDS):
            raise ValueError('Native invocation counter moved backwards')
        if role == 'interpreted' and any(row[key] for key in NATIVE_SAMPLE_FIELDS):
            raise ValueError('Interpreted invocation contains native activity')
        previous = row
    return observation


def validate_native_sample_totals(observations, native, role, label):
    """Bind optional historical metadata to this exact owner and its independently parsed final receipt."""
    group = observations.get('native_sample')
    if group is None:
        # Old canonical artifacts remain readable; diagnostics requiring per-call evidence must demand it.
        return None
    if (not isinstance(native, dict) or not {'fragments', 'calls', 'operations', 'code_bytes'} <= set(native)
            or not isinstance(group, dict) or set(group) != {label}):
        raise ValueError('Foreign native invocation owner')
    observation = validate_native_sample_log(group[label], role)
    final = observation['samples'][-1]
    if any(final[key] != native[key] for key in NATIVE_SAMPLE_FIELDS if key in native):
        raise ValueError('Native invocation observations disagree with final owner')
    return observation


def _native_invocation_activity(rows, sample):
    """Derive guest work and observed owner state from validated post-clock checkpoints, never time.

    Publication/occupancy observations can include asynchronous progress between calls; they are
    not clocks or proof of the exact executor-entry footprint. The caller proves index 0..12.
    """
    current = rows[sample]
    previous = rows[sample-1] if sample else dict.fromkeys(NATIVE_SAMPLE_FIELDS, 0)
    return dict(fragments=current['fragments'], observed_publications=current['fragments']-previous['fragments'],
                previous_code_bytes=previous['code_bytes'], code_bytes=current['code_bytes'],
                **{key: current[key]-previous[key] for key in ('calls', 'operations', 'branches', 'headers')})


def match_measured_native_invocations(measured, profiled, role):
    """Require exact cold/reused work and code histories; retain explicit differences in excluded warmups."""
    canonical_rows = validate_native_sample_log(measured, role)['samples']
    profiled_rows = validate_native_sample_log(profiled, role)['samples']
    canonical = [_native_invocation_activity(canonical_rows, sample) for sample in range(13)]
    observed = [_native_invocation_activity(profiled_rows, sample) for sample in range(13)]
    for sample in MEASURED_NATIVE_SAMPLES:
        # Changed guest work or observed owner state at any measured call refuses attribution.
        if canonical[sample] != observed[sample]:
            raise ValueError('Profile changed measured native execution or code working set at call '+str(sample))
    return dict(measured_samples=list(MEASURED_NATIVE_SAMPLES),
                warmup_differences=[sample for sample in (1, 2) if canonical[sample] != observed[sample]],
                canonical=measured['samples'], profiled=profiled['samples'],
                cold=canonical[0], reused=canonical[12])
