# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Validate actual retained PolkaVM interpreter instances without running code or inventing clocks.

Every case owns one instance, separate construction/destruction observations, and complete cache
continuity receipts around invocation restoration and execution. Zero subsidiary clock deltas
remain genuine observations below the clock's resolution; execution clocks are validated elsewhere.
"""
import re

CODE_LIFETIME = 'retained-code-v1'
INSTANCE_KEYS = {'version', 'label', 'instances', 'constructor_cpu_ns', 'constructor_wall_ns',
                 'initial_cache_bytes', 'teardown_cpu_ns', 'teardown_wall_ns', 'samples'}
SAMPLE_KEYS = {'sample', 'restore_cpu_ns', 'restore_wall_ns', 'before_reset_bytes',
               'after_reset_bytes', 'after_run_bytes'}


def _integer(value):
    """Keep exact nonnegative sub-scope clocks/counters, rejecting booleans and lossy values."""
    if type(value) is not int or not 0 <= value < 1 << 63:
        raise ValueError('Invalid retained reference integer')
    return value


def validate_instance(value, label, count=13):
    """Require one cold instance and an unbroken, nonempty cache across every restored call."""
    if (not isinstance(value, dict) or set(value) != INSTANCE_KEYS or
            value.get('label') != label or type(value.get('version')) is not int or
            value['version'] != 1 or type(value.get('instances')) is not int or value['instances'] != 1):
        raise ValueError('Invalid retained reference instance identity')
    for key in INSTANCE_KEYS-{'version', 'label', 'instances', 'samples'}:
        _integer(value[key])
    if value['initial_cache_bytes'] != 0:
        raise ValueError('Retained reference instance did not start cold')
    samples = value['samples']
    if not isinstance(samples, list) or len(samples) != count:
        raise ValueError('Incomplete retained reference samples')
    previous = value['initial_cache_bytes']
    for index, sample in enumerate(samples):
        # Restoring data/registers must preserve the exact previous code-cache extent, not warm it.
        if not isinstance(sample, dict) or set(sample) != SAMPLE_KEYS:
            raise ValueError('Invalid retained reference sample')
        for number in sample.values():
            _integer(number)
        if (sample['sample'] != index or sample['before_reset_bytes'] != previous or
                sample['after_reset_bytes'] != previous or
                sample['after_run_bytes'] < previous or sample['after_run_bytes'] == 0):
            raise ValueError('Retained reference cache continuity disagreement')
        previous = sample['after_run_bytes']
    return value


def reference_instances(output, labels, count=13):
    """Strip only complete ordered lifetime receipts and return the untouched call grammar separately."""
    if (not isinstance(output, str) or not labels or len(set(labels)) != len(labels) or
            any(not isinstance(label, str) or re.fullmatch('[a-z0-9-]{1,64}', label) is None
                for label in labels)):
        raise ValueError('Invalid retained reference process labels')
    calls, records = [], []
    for line in output.splitlines():
        # Prefix recognition also routes malformed versions/kinds to the strict receipt consumer.
        if line.startswith(('REFERENCE_INSTANCE', 'REFERENCE_RESTORE', 'REFERENCE_CACHE')):
            records.append(line.split(','))
        else:
            calls.append(line)
    position = 0

    def record(kind, label, fields):
        """Consume exactly one source-bound receipt; absent, duplicated or reordered records fail."""
        nonlocal position
        row = records[position] if position < len(records) else []
        position += 1
        if len(row) != fields or row[:3] != [kind, '1', label]:
            raise ValueError('Missing or foreign retained reference '+kind)
        if any(re.fullmatch('0|[1-9][0-9]*', number) is None for number in row[3:]):
            raise ValueError('Malformed retained reference integer')
        return [_integer(int(number)) for number in row[3:]]

    result = {}
    for label in labels:
        constructor_cpu, constructor_wall, initial = record('REFERENCE_INSTANCE', label, 6)
        value = dict(version=1, label=label, instances=1, constructor_cpu_ns=constructor_cpu,
                     constructor_wall_ns=constructor_wall, initial_cache_bytes=initial, samples=[])
        for index in range(count):
            # Each successful validation binds both restoration clocks and actual public cache sizes.
            restored, cpu, wall = record('REFERENCE_RESTORE', label, 6)
            sampled, before, after_reset, after_run = record('REFERENCE_CACHE', label, 7)
            if restored != index or sampled != index:
                raise ValueError('Unordered retained reference sample')
            value['samples'].append(dict(sample=index, restore_cpu_ns=cpu, restore_wall_ns=wall,
                before_reset_bytes=before, after_reset_bytes=after_reset, after_run_bytes=after_run))
        cpu, wall = record('REFERENCE_INSTANCE_DROP', label, 5)
        value.update(teardown_cpu_ns=cpu, teardown_wall_ns=wall)
        result[label] = validate_instance(value, label, count)
    if position != len(records):
        raise ValueError('Foreign retained reference receipts')
    return '\n'.join(calls)+'\n', result


def validate_invocation_instance(value, label, count=13):
    """Validate clock-free cache continuity receipts inside actual full-call boundaries."""
    keys = {'version', 'label', 'instances', 'initial_cache_bytes', 'samples'}
    sample_keys = {'sample', 'before_reset_bytes', 'after_reset_bytes', 'after_run_bytes'}
    if (not isinstance(value, dict) or set(value) != keys or value.get('label') != label or
            type(value.get('version')) is not int or value['version'] != 2 or
            type(value.get('instances')) is not int or value['instances'] != 1):
        raise ValueError('Invalid full-invocation reference instance')
    if _integer(value['initial_cache_bytes']) != 0:
        raise ValueError('Full-invocation reference instance did not start cold')
    if not isinstance(value['samples'], list) or len(value['samples']) != count:
        raise ValueError('Incomplete full-invocation reference samples')
    previous = 0
    for index, sample in enumerate(value['samples']):
        if not isinstance(sample, dict) or set(sample) != sample_keys:
            raise ValueError('Unexpected full-invocation subsidiary clock or cache receipt')
        for number in sample.values():
            _integer(number)
        if (sample['sample'] != index or sample['before_reset_bytes'] != previous or
                sample['after_reset_bytes'] != previous or sample['after_run_bytes'] < previous or
                sample['after_run_bytes'] == 0):
            raise ValueError('Full-invocation reference cache discontinuity')
        previous = sample['after_run_bytes']
    return value


def invocation_reference_instances(output, labels, count=13):
    """Strip version2 receipts without manufacturing unavailable constructor/restore/drop clocks."""
    if (not isinstance(output, str) or not labels or len(set(labels)) != len(labels) or
            any(not isinstance(label, str) or re.fullmatch('[a-z0-9-]{1,64}', label) is None
                for label in labels)):
        raise ValueError('Invalid full-invocation reference process labels')
    calls, records = [], []
    for line in output.splitlines():
        if line.startswith(('REFERENCE_INSTANCE', 'REFERENCE_RESTORE', 'REFERENCE_CACHE')):
            records.append(line.split(','))
        else:
            calls.append(line)
    position = 0

    def record(kind, label, fields):
        nonlocal position
        row = records[position] if position < len(records) else []
        position += 1
        if len(row) != fields or row[:3] != [kind, '2', label]:
            raise ValueError('Missing or foreign full-invocation '+kind)
        if any(re.fullmatch('0|[1-9][0-9]*', number) is None for number in row[3:]):
            raise ValueError('Malformed full-invocation reference integer')
        return [_integer(int(number)) for number in row[3:]]

    result = {}
    for label in labels:
        initial, = record('REFERENCE_INSTANCE', label, 4)
        value = dict(version=2, label=label, instances=1, initial_cache_bytes=initial, samples=[])
        for index in range(count):
            sample, before, restored, after = record('REFERENCE_CACHE', label, 7)
            if sample != index:
                raise ValueError('Unordered full-invocation reference sample')
            value['samples'].append(dict(sample=index, before_reset_bytes=before,
                after_reset_bytes=restored, after_run_bytes=after))
        record('REFERENCE_INSTANCE_DROP', label, 3)
        result[label] = validate_invocation_instance(value, label, count)
    if position != len(records):
        raise ValueError('Foreign full-invocation reference receipts')
    return '\n'.join(calls)+'\n', result
