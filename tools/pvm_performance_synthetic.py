# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Parse complete current-source synthetic cohorts with genuine, distinct CPU and wall clocks.

The versioned protocol is opt-in for the maintained native/reference drivers. Legacy wall-only
records cannot enter this parser. Parsing never builds, runs, aggregates or substitutes a backend.
"""
import re

from pvm_benchmark_report import NAMES
from pvm_comparison_policy import policy_receipt
from pvm_reference_lifetime import reference_instances, invocation_reference_instances
from pvm_invocation_scope import invocation_scope, scope_diagnostics, full_parsed

NATIVE_FIELDS = ('fragments', 'calls', 'operations', 'code_bytes', 'compilation_ns')


def integers(fields, positive=False):
    """Reject signs, whitespace, leading zeros, oversized values and false zero durations."""
    if any(re.fullmatch(r'0|[1-9][0-9]{0,19}', value) is None for value in fields):
        raise ValueError('Malformed synthetic integer')
    values = [int(value) for value in fields]
    if any(value >= 2**63 or (positive and value == 0) for value in values):
        raise ValueError('Invalid synthetic duration/counter')
    return values


def parse_synthetic(output, role, require_full=False):
    """Return all eleven normalized case records only after exact ordered framing validates.

    Full-call constructors are nested diagnostics; historical execution-only constructors retain
    their original separate meaning. CPU/wall samples and actual policy/native receipts must agree.
    Reference identity requires
    an actual interpreted module with zero compiled bytes and never supplies native-owner data.
    """
    if role not in ('interpreted', 'jit', 'reference') or not isinstance(output, str):
        raise ValueError('Unknown synthetic role/output')
    output, full = invocation_scope(output, require_full)
    observed_scope = None
    if full:
        output, observed_scope = scope_diagnostics(output, role)
    instances = {}
    if role == 'reference':
        # Canonical reference calls retain the same actual interpreter cache across all thirteen runs.
        parser = invocation_reference_instances if full else reference_instances
        output, instances = parser(output, [f'synthetic-{row}' for row in range(11)])
    lines = output.splitlines()
    position = 0

    def record(kind, row, count):
        """Consume one exact version/row record; missing, duplicated or reordered lines fail."""
        nonlocal position
        fields = lines[position].split(',') if position < len(lines) else []
        position += 1
        if len(fields) != count or fields[:3] != [kind, '1', str(row)]:
            raise ValueError('Missing or foreign synthetic '+kind+' record')
        return fields[3:]

    cases = {}
    for row, name in enumerate(NAMES):
        # A constructor belongs to exactly this immutable program and precedes its cold sample.
        cpu, wall = integers(record('SYNTHETIC_PREPARE', row, 5), positive=not full)
        execution = dict(preparation_ns=[cpu], preparation_wall_ns=[wall], samples=[])
        if role == 'reference':
            identity = record('SYNTHETIC_REFERENCE', row, 6)
            if identity != ['interpreter', 'interpreter', '0']:
                raise ValueError('Synthetic reference must be actual PolkaVM interpreted')
            execution['reference'] = dict(requested='interpreter', actual='interpreter', machine_code_bytes=0)
            execution['reference_instance'] = instances[f'synthetic-{row}']
        for sample in range(13):
            # Ordering binds all warmups/cold/reused calls; no filtering or process pooling occurs.
            observed, cpu, wall = integers(record('SYNTHETIC_SAMPLE', row, 6))
            if observed != sample or cpu <= 0 or wall <= 0:
                raise ValueError('Unordered or nonpositive synthetic sample')
            execution['samples'].append(dict(sample=sample, cpu_ns=cpu, wall_ns=wall))
        native = policy = None
        if role != 'reference':
            # Public copied counters are separate from actual-policy identity and cross-checked below.
            native = dict(zip(NATIVE_FIELDS, integers(record('SYNTHETIC_NATIVE', row, 8))))
            fields = record('SYNTHETIC_POLICY', row, 11)
            _, policy = policy_receipt('PVM_POLICY,1,'+','.join(fields)+'\n', role)
            if any(native[key] != policy[key] for key in ('fragments', 'calls', 'operations')):
                raise ValueError('Synthetic policy/native counters disagree')
            if role == 'jit' and not (policy['jit_built'] and policy['platform_supported']):
                raise ValueError('Synthetic JIT policy requires the supported production native build')
            if role == 'interpreted' and any(native.values()):
                raise ValueError('Interpreted synthetic owner contains native work')
            if (native['fragments'] > 8192 or native['code_bytes'] > 1024*1024
                    or native['code_bytes'] and not native['fragments']
                    or not full and bool(native['fragments']) != bool(native['code_bytes'])):
                raise ValueError('Invalid synthetic native code occupancy')
        cases[name] = dict(execution=execution, native=native, policy=policy)
    if lines[position:] != ['SYNTHETIC_OK,1,'+role]:
        raise ValueError('Missing or foreign synthetic terminal success')
    if full:
        return {name: full_parsed(parsed, observed_scope, f"synthetic-{NAMES.index(name)}")
                for name, parsed in cases.items()}
    return cases
