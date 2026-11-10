# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Canonical full-call identity and strict opt-in framing; legacy clocks are never relabelled."""
import re

BOUNDARY = 'full-invocation-v1'
OUTPUT = 'consume-before-reuse-v1'
CPU_CLOCK = 'process-cpu'
INPUT = 'program-state-host-inputs-v1'
PRESTARTED = 'prestarted'
DEMAND_STARTED = 'demand-started'
RUNTIME_START_POLICIES = (DEMAND_STARTED, PRESTARTED)
SCOPE_HEADER = f'PVM_MEASURE_SCOPE,1,{BOUNDARY},{OUTPUT},{CPU_CLOCK}'


def measurement_identity():
    """Return independent metadata for one declared semantic request and consumed result."""
    return dict(boundary=BOUNDARY, output=OUTPUT, cpu_clock=CPU_CLOCK, input=INPUT)


def invocation_scope(output, required=False):
    """Consume the sole leading scope receipt; reject malformed, duplicate or misplaced receipts."""
    lines = output.splitlines()
    present = [index for index, line in enumerate(lines) if line.startswith('PVM_MEASURE_SCOPE')]
    if not present:
        if required:
            raise ValueError('Missing full-invocation scope receipt')
        return output, False
    if present != [0] or lines[0] != SCOPE_HEADER:
        raise ValueError('Foreign or unordered full-invocation scope receipt')
    return '\n'.join(lines[1:])+'\n', True



def scope_diagnostics(output, role):
    """Consume actual runtime/owner observations, retaining explicit unavailable subsidiary clocks."""
    calls, diagnostics = [], {}
    for line in output.splitlines():
        if not line.startswith(('PVM_RUNTIME_', 'PVM_OWNER_WINDOW', 'PVM_NATIVE_COMPILATION')):
            calls.append(line)
            continue
        fields = line.split(',')
        kind = fields[0]
        if len(fields) < 3 or fields[1] != '1' or re.fullmatch('[a-z0-9-]{1,64}', fields[2]) is None:
            raise ValueError('Malformed invocation lifecycle identity')
        label = fields[2]
        key = (kind, label)
        if key in diagnostics:
            raise ValueError('Duplicate invocation lifecycle observation')
        def number(text):
            if re.fullmatch('0|[1-9][0-9]{0,18}', text) is None or int(text) >= 1 << 63:
                raise ValueError('Invalid invocation lifecycle integer')
            return int(text)
        if kind == 'PVM_RUNTIME_OWNER' and len(fields) == 6:
            if (fields[3] != 'application-process' or fields[4] not in RUNTIME_START_POLICIES or
                    not 1 <= number(fields[5]) <= 11):
                raise ValueError('Foreign runtime lifecycle ownership')
            value = dict(ownership=fields[3], creation=fields[4], code_owners=number(fields[5]))
        elif kind == 'PVM_RUNTIME_NONE' and len(fields) == 5:
            if fields[3] != 'interpreted-policy' or not 1 <= number(fields[4]) <= 11:
                raise ValueError('Foreign no-runtime lifecycle reason')
            value = dict(reason=fields[3], code_owners=number(fields[4]))
        elif kind in ('PVM_RUNTIME_CLOSE', 'PVM_OWNER_WINDOW') and len(fields) == (5 if kind == 'PVM_RUNTIME_CLOSE' else 6):
            if kind == 'PVM_OWNER_WINDOW' and fields[5] != 'includes-driver-oracles':
                raise ValueError('Owner diagnostic cannot masquerade as PVM-only CPU/wall')
            value = dict(cpu_ns=number(fields[3]), wall_ns=number(fields[4]))
            if kind == 'PVM_OWNER_WINDOW': value['includes_driver_oracles'] = True
        elif kind == 'PVM_NATIVE_COMPILATION' and len(fields) == 5 and fields[3] in ('0', '1'):
            measured, raw = fields[3] == '1', number(fields[4])
            value = dict(measured=measured, accounting_raw_ns=raw,
                         clock='supplementary-process-cpu' if measured else 'unavailable')
        else:
            raise ValueError('Foreign invocation lifecycle record')
        if role == 'reference' and kind != 'PVM_OWNER_WINDOW':
            raise ValueError('Interpreter reference cannot supply native runtime diagnostics')
        diagnostics[key] = value
    # Diagnostics are never summed into primary call clocks. Reference clocks may honestly be absent.
    owners = {label for kind, label in diagnostics if kind == 'PVM_RUNTIME_OWNER'}
    closes = {label for kind, label in diagnostics if kind == 'PVM_RUNTIME_CLOSE'}
    windows = {label for kind, label in diagnostics if kind == 'PVM_OWNER_WINDOW'}
    absent = {label for kind, label in diagnostics if kind == 'PVM_RUNTIME_NONE'}
    if role == 'jit' and (len(owners) != 1 or owners != closes or not owners <= windows or absent):
        raise ValueError('Missing or discontinuous JIT application runtime lifecycle')
    if role == 'interpreted' and (len(absent) != 1 or not absent <= windows or owners or closes):
        raise ValueError('Interpreted policy requires an explicit absent compiler runtime')
    result = {}
    for (kind, label), value in diagnostics.items():
        result.setdefault(kind.removeprefix('PVM_').lower(), {})[label] = value
    return '\n'.join(calls)+'\n', result



def validate_scope_observations(value, role):
    """Revalidate structured lifecycle metadata independently of its untrusted artifact envelope."""
    kinds = {'runtime_owner', 'runtime_none', 'runtime_close', 'owner_window', 'native_compilation'}
    if not isinstance(value, dict) or set(value)-kinds or not value.get('owner_window'):
        raise ValueError('Missing invocation owner diagnostics')
    def integer(number):
        if type(number) is not int or not 0 <= number < 1 << 63:
            raise ValueError('Invalid structured lifecycle integer')
    for kind, rows in value.items():
        if not isinstance(rows, dict) or not rows:
            raise ValueError('Invalid lifecycle observation group')
        for label, observation in rows.items():
            if not isinstance(label, str) or re.fullmatch('[a-z0-9-]{1,64}', label) is None or not isinstance(observation, dict):
                raise ValueError('Invalid lifecycle observation identity')
            if kind == 'runtime_owner':
                if (set(observation) != {'ownership', 'creation', 'code_owners'} or
                        observation['ownership'] != 'application-process' or
                        observation['creation'] not in RUNTIME_START_POLICIES):
                    raise ValueError('Foreign application runtime ownership')
                integer(observation['code_owners'])
                if not 1 <= observation['code_owners'] <= 11:
                    raise ValueError('Invalid application runtime code-owner count')
            elif kind == 'runtime_none':
                if set(observation) != {'reason', 'code_owners'} or observation['reason'] != 'interpreted-policy':
                    raise ValueError('Foreign no-runtime lifecycle identity')
                integer(observation['code_owners'])
                if not 1 <= observation['code_owners'] <= 11:
                    raise ValueError('Invalid no-runtime code-owner count')
            elif kind == 'native_compilation':
                if (set(observation) != {'measured', 'accounting_raw_ns', 'clock'} or
                        type(observation['measured']) is not bool or observation['clock'] !=
                        ('supplementary-process-cpu' if observation['measured'] else 'unavailable')):
                    raise ValueError('Foreign compilation clock availability')
                integer(observation['accounting_raw_ns'])
            else:
                keys = {'cpu_ns', 'wall_ns'} | ({'includes_driver_oracles'} if kind == 'owner_window' else set())
                if set(observation) != keys or kind == 'owner_window' and observation['includes_driver_oracles'] is not True:
                    raise ValueError('Foreign owner-window clock scope')
                integer(observation['cpu_ns'])
                integer(observation['wall_ns'])
    if role == 'reference':
        if set(value) != {'owner_window'}:
            raise ValueError('Interpreter reference has native runtime diagnostics')
    elif role == 'interpreted':
        absent = value.get('runtime_none', {})
        if (len(absent) != 1 or not set(absent) <= set(value['owner_window']) or
                'runtime_owner' in value or 'runtime_close' in value or not value.get('native_compilation')):
            raise ValueError('Interpreted policy cannot own or close a compiler runtime')
        if any(row['measured'] or row['accounting_raw_ns'] for row in value['native_compilation'].values()):
            raise ValueError('Interpreted no-runtime policy cannot measure native compilation')
    elif (role != 'jit' or len(value.get('runtime_owner', {})) != 1 or
          set(value['runtime_owner']) != set(value.get('runtime_close', {})) or
          not set(value['runtime_owner']) <= set(value['owner_window']) or
          'runtime_none' in value or not value.get('native_compilation')):
        raise ValueError('Incomplete JIT runtime lifecycle or compilation availability')
    return value


def full_parsed(parsed, observed=None, label=None):
    """Keep primary enclosing clocks separate from genuine optional component diagnostics."""
    invocation = parsed.pop('execution')
    diagnostics = {key: invocation.pop(key) for key in list(invocation)
                   if key not in ('samples', 'reference_instance', 'reference')}
    if observed is not None:
        observed = {kind: dict(rows) for kind, rows in observed.items()}
        if label in observed.get('owner_window', {}):
            observed['owner_window'] = {label: observed['owner_window'][label]}
        if parsed.get('native') is not None:
            compilation = observed.get('native_compilation', {}).get(label)
            if compilation is None:
                raise ValueError('Missing explicit native compilation clock availability')
            observed['native_compilation'] = {label: compilation}
            raw = parsed['native'].get('compilation_ns')
            if raw is not None and raw != compilation['accounting_raw_ns']:
                raise ValueError('Contradictory native compilation accounting')
        diagnostics['scope_observations'] = validate_scope_observations(
            observed, 'reference' if parsed.get('native') is None else parsed['policy']['requested'])
    native = parsed.get('native')
    if native is not None and 'compilation_ns' in native:
        diagnostics['native_compilation_accounting_raw_ns'] = native.pop('compilation_ns')
    invocation['measurement'] = measurement_identity()
    parsed.update(invocation=invocation, diagnostics=diagnostics)
    return parsed
