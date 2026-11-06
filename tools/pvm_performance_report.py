# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Validate and publish the one current-source native PVM performance protocol.

Every accepted cell retains thirteen actual CPU/wall samples, its immutable process identity and
truthful runtime policy. Rendering recomputes statistics; it never launches tools or guest code.
"""
import copy
from functools import wraps
import csv
import io
import json
import os
from pathlib import Path
import re
import statistics
import tempfile

from pvm_benchmark_report import NAMES
from pvm_sieve_report import limits_for_guest
from pvm_reference_lifetime import CODE_LIFETIME, validate_invocation_instance
from pvm_invocation_scope import measurement_identity, validate_scope_observations
import pvm_performance_history_v1 as history_v1
import pvm_performance_history_v2 as history_v2

SCHEMA = 'pvm-performance-v3'
ROLES = ('interpreted', 'jit', 'reference')
ORDERS = (ROLES, ROLES[::-1])
ARCHITECTURES = ('arm64', 'x86_64')
NATIVE_KEYS = ('fragments', 'calls', 'operations')
OPTIONAL_NATIVE_KEYS = ('code_bytes', 'compilation_ns', 'branches', 'headers')


def historical_reader(schema):
    """Return a frozen historical reader; unsupported schemas never become the current cohort."""
    readers = {history_v1.SCHEMA: history_v1, history_v2.SCHEMA: history_v2}
    if schema not in readers:
        raise ValueError('Unknown PVM performance schema')
    return readers[schema]


def schema_reader(function):
    """Keep rendering/export of explicit historical data separate from canonical v3 validation."""
    @wraps(function)
    def read(report, *args, **kwargs):
        if isinstance(report, dict) and report.get('schema') != SCHEMA:
            return getattr(historical_reader(report.get('schema')), function.__name__)(report, *args, **kwargs)
        return function(report, *args, **kwargs)
    return read


def validate_current_report(report):
    """Require the full-call cohort at producer/latest boundaries, even though history remains readable."""
    if not isinstance(report, dict) or report.get('schema') != SCHEMA:
        raise ValueError('Historical execution-only data is not full-invocation evidence')
    return validate_report(report)


def case_inventory(scope='all'):
    """Return fresh current workload records without a native-readiness or operation-count floor."""
    if scope not in ('all', 'micro', 'doom'):
        raise ValueError('Unknown PVM performance scope')
    rows = []
    if scope != 'doom':
        # Synthetic names and guest sizes remain owned by the existing maintained protocols.
        rows += [dict(case_id=name, case=name, limit=0, family='synthetic', native_required=[])
                 for name in NAMES]
        for guest in ('sieve', 'minimal', 'memset', 'pinky'):
            for limit in limits_for_guest(guest):
                required = []
                rows.append(dict(case_id=f'{guest}-{limit}', case=guest, limit=limit,
                                 family='guest', native_required=required))
    if scope != 'micro':
        # Readiness is observed without waits or a native-operation floor, including incomplete coverage.
        rows += [dict(case_id='doom-'+phase, case=phase, limit=0, family='doom',
                      native_required=[]) for phase in ('init', 'tick')]
    return rows


def _integer(value, label, minimum=0, maximum=(1 << 64)-1):
    """Reject booleans, lossy floats and out-of-range duration/counter identities."""
    if type(value) is not int or not minimum <= value <= maximum:
        raise ValueError('Invalid '+label)
    return value


def _digest(value, label, width=64):
    """Accept one exact lowercase immutable digest, never a branch name or malformed placeholder."""
    if not isinstance(value, str) or re.fullmatch('[0-9a-f]{'+str(width)+'}', value) is None:
        raise ValueError('Invalid '+label)
    return value


def _mapping(value, label):
    """Refuse default/malformed records before any nested fields are inspected."""
    if not isinstance(value, dict):
        raise ValueError('Missing '+label)
    return value


def _text(value, label):
    """Require an actual bounded identity string, without interpreting its contents as commands."""
    if not isinstance(value, str) or not value or len(value) > 16384:
        raise ValueError('Invalid '+label)
    return value


def _architecture(machine):
    """Normalize only the native spellings used by the maintained Linux host receipt."""
    aliases = {'arm64': 'arm64', 'aarch64': 'arm64', 'ARM64': 'arm64',
               'x86_64': 'x86_64', 'amd64': 'x86_64', 'AMD64': 'x86_64', 'X64': 'x86_64'}
    if not isinstance(machine, str) or machine not in aliases:
        raise ValueError('Unsupported native architecture')
    return aliases[machine]


def _identity(report):
    """Bind source, native host, qualification, compiler, CI and sealed inputs to this report."""
    revision = _digest(report.get('revision'), 'revision', 40)
    arch = report.get('architecture')
    if arch not in ARCHITECTURES:
        raise ValueError('Invalid report architecture')
    identity = _mapping(report.get('identity'), 'identity')
    if identity.get('code_lifetime') != CODE_LIFETIME:
        raise ValueError('Foreign prepared/reference code lifetime')
    host = _mapping(identity.get('host'), 'native host')
    runner = _mapping(host.get('runner'), 'Actions host')
    uname = host.get('uname')
    if (host.get('system') != 'Linux' or host.get('architecture') != arch
            or _architecture(host.get('machine')) != arch
            or not isinstance(uname, list) or len(uname) != 2 or uname[0] != 'Linux'
            or _architecture(uname[1]) != arch
            or _architecture(runner.get('RUNNER_ARCH')) != arch):
        raise ValueError('Native host identity disagreement')
    ci = _mapping(identity.get('ci'), 'CI identity')
    for key in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'):
        # Actions exposes decimal strings; reject missing IDs and ambiguous leading-zero identities.
        if re.fullmatch(r'[1-9][0-9]*', str(ci.get(key, ''))) is None:
            raise ValueError('Invalid '+key)
    if (ci.get('GITHUB_SHA') != revision or ci.get('GITHUB_EVENT_NAME') not in
            ('push', 'workflow_dispatch', 'pull_request')):
        raise ValueError('CI source/event disagreement')
    for key in ('GITHUB_REF', 'GITHUB_REPOSITORY'):
        _text(ci.get(key), key)
    # Bind matrix presentation to the actual workflow receipt; retrieval never guesses job names.
    if ci.get('GITHUB_JOB') != 'pvm-comparison':
        raise ValueError('Foreign PVM workflow job')
    if not _text(ci.get('PVM_CI_JOB_NAME'), 'PVM CI job name').strip():
        raise ValueError('Blank PVM CI job name')
    if re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', ci['GITHUB_REPOSITORY']) is None:
        raise ValueError('Invalid CI repository')
    files = _mapping(identity.get('files'), 'sealed file identities')
    if not files:
        raise ValueError('Empty sealed file identities')
    for name, digest in files.items():
        _text(name, 'sealed file path')
        _digest(digest, 'sealed file hash')
    compiler = _mapping(identity.get('compiler'), 'compiler identity')
    if _digest(compiler.get('sha256'), 'compiler hash') not in files.values():
        raise ValueError('Compiler is absent from sealed files')
    _text(compiler.get('identity'), 'compiler version')
    qualification = _mapping(identity.get('native_qualification'), 'native qualification')
    if (qualification.get('path') != 'build/tests/pvm-native/results.json' or
            qualification.get('revision') != revision or
            not any(name.endswith('/'+str(qualification.get('path', ''))) and value ==
                    qualification.get('sha256') for name, value in files.items())):
        raise ValueError('Native qualification source/file disagreement')
    _digest(qualification.get('sha256'), 'qualification hash')
    _digest(identity.get('reference_revision'), 'reference revision', 40)
    _mapping(identity.get('toolchain'), 'pinned toolchain')
    expected_define = 'pvmArm64Jit' if arch == 'arm64' else 'pvmX86Jit'
    if identity.get('native_build_defines') != [expected_define]:
        raise ValueError('Wrong native production build profile')
    if report['scope'] != 'micro':
        doom = _mapping(identity.get('doom'), 'canonical DOOM identity')
        _integer(identity.get('doom_warmup_ticks'), 'canonical DOOM preparation cohort', 1320, 1320)
        _integer(doom.get('warmup_ticks'), 'canonical DOOM preparation cohort', 1320, 1320)
        _digest(doom.get('golden_rgba_sha256'), 'upstream DOOM golden')
    return identity


def _command(record, files, positive=True):
    """Tie each successful or refused process to a sealed executable and retained log."""
    record = _mapping(record, 'process evidence')
    command = record.get('command')
    if (not isinstance(command, list) or not command or
            any(not isinstance(arg, str) or not arg for arg in command)):
        raise ValueError('Invalid process command identity')
    if command[0] not in files:
        raise ValueError('Unsealed process executable')
    _text(record.get('log'), 'process log')
    code = _integer(record.get('exit_code'), 'process exit', -(1 << 31), (1 << 31)-1)
    if (code == 0) != positive:
        raise ValueError('Process/control exit disagreement')
    return command[0]


def _policy(parsed, role):
    """Validate actual policy and per-cell eligibility without demanding native work from every micro."""
    native, policy = parsed.get('native'), parsed.get('policy')
    if role == 'reference':
        if native is not None or policy is not None:
            raise ValueError('Reference cannot carry independent native/policy counters')
        reference = parsed['invocation'].get('reference')
        if reference is not None:
            reference = _mapping(reference, 'reference backend receipt')
            if (reference.get('requested') != 'interpreter' or reference.get('actual') !=
                    'interpreter' or type(reference.get('machine_code_bytes')) is not int or
                    reference['machine_code_bytes'] != 0):
                raise ValueError('Foreign reference backend receipt')
        return
    native = _mapping(native, 'native counters')
    policy = _mapping(policy, 'runtime policy')
    if set(native)-set(NATIVE_KEYS+OPTIONAL_NATIVE_KEYS):
        raise ValueError('Unknown native counter')
    for key in NATIVE_KEYS:
        _integer(native.get(key), 'native '+key)
        if policy.get(key) != native[key] or type(policy.get(key)) is not int:
            raise ValueError('Policy/native counter disagreement')
    for key in OPTIONAL_NATIVE_KEYS:
        if key in native:
            _integer(native[key], 'native '+key)
    if any(type(policy.get(key)) is not bool for key in
           ('jit_built', 'platform_supported', 'fallback_enabled')):
        raise ValueError('Invalid policy availability')
    actual = 'jit' if native['operations'] else 'interpreted'
    if (type(policy.get('version')) is not int or policy['version'] != 1 or policy.get('requested') != role or
            policy.get('actual') != actual or not policy['jit_built'] or
            not policy['platform_supported'] or policy['fallback_enabled'] != (role == 'jit')):
        raise ValueError('Requested/actual native policy disagreement')
    if native.get('code_bytes', 0) and not native['fragments']:
        raise ValueError('Native code occupancy requires a collected image')
    if ((native['operations'] and not native['calls']) or
            (native['calls'] and not native['fragments']) or
            (role == 'interpreted' and any(native.values()))):
        raise ValueError('Impossible or leaked native work')
    if (native.get('branches', 0) > native['calls'] or native.get('headers', 0) > native['calls'] or
            ('branches' in native and 'headers' in native and native['headers'] > native['branches'])):
        raise ValueError('Impossible native control counters')


def _execution(execution, reference_label=None):
    """Validate all call clocks and independently retained reference-instance evidence."""
    execution = _mapping(execution, 'full-invocation samples')
    if execution.get('measurement') != measurement_identity():
        raise ValueError('Foreign invocation boundary/output/input/clock')
    if set(execution)-{'samples', 'measurement', 'reference_instance', 'reference'}:
        raise ValueError('Component clocks cannot masquerade as primary invocation data')
    samples = execution.get('samples')
    if not isinstance(samples, list) or len(samples) != 13:
        raise ValueError('Incomplete thirteen-sample process')
    for index, sample in enumerate(samples):
        sample = _mapping(sample, 'sample')
        if type(sample.get('sample')) is not int or sample['sample'] != index:
            raise ValueError('Unordered sample identity')
        for clock in ('cpu_ns', 'wall_ns'):
            _integer(sample.get(clock), clock, 1, (1 << 63)-1)
    if 'lifecycle' in execution:
        raise ValueError('Fresh-instance lifecycle cannot enter a retained-code cohort')
    if reference_label is not None:
        validate_invocation_instance(execution.get('reference_instance'), reference_label)
    elif 'reference_instance' in execution:
        raise ValueError('Independent engine cannot supply reference-instance evidence')


@schema_reader
def validate_report(report):
    """Return a complete passed report unchanged, or reject its source/coverage/sample evidence."""
    report = _mapping(report, 'performance report')
    if report.get('schema') != SCHEMA or report.get('status') != 'passed':
        raise ValueError('Performance report is not a passed canonical protocol')
    inventory = case_inventory(report.get('scope'))
    cases = {row['case_id']: row for row in inventory}
    identity = _identity(report)
    if identity.get('measurement') != measurement_identity():
        raise ValueError('Missing full-invocation cohort identity')
    files = identity['files']
    expected = {(case, role, order) for case in cases for role in ROLES for order in (0, 1)}
    seen, images, role_orders = set(), {}, {}
    runs = report.get('runs')
    if not isinstance(runs, list) or len(runs) != len(expected):
        raise ValueError('Incomplete case/role/order matrix')
    for row in runs:
        row = _mapping(row, 'process row')
        _text(row.get('case_id'), 'case ID')
        _text(row.get('role'), 'process role')
        key = (row.get('case_id'), row.get('role'), row.get('order'))
        if type(row.get('order')) is not int or key not in expected or key in seen:
            raise ValueError('Foreign or duplicate process cell')
        seen.add(key)
        case = cases[key[0]]
        if row.get('case') != case['case'] or type(row.get('limit')) is not int or row['limit'] != case['limit']:
            raise ValueError('Case/limit identity disagreement')
        parsed = _mapping(row.get('parsed'), 'parsed process')
        label = None
        if key[1] == 'reference':
            label = ('synthetic-'+str(NAMES.index(case['case_id'])) if case['family'] == 'synthetic'
                     else case['case_id'])
        _execution(parsed.get('invocation'), label)
        if 'execution' in parsed:
            raise ValueError('Execution-only samples cannot coexist with the full-call cohort')
        diagnostics = _mapping(parsed.get('diagnostics'), 'full-call diagnostics')
        if parsed.get('native') is not None and 'compilation_ns' in parsed['native']:
            raise ValueError('Native accounting is not an available compilation clock')
        for clock in ('preparation_ns', 'preparation_wall_ns'):
            if clock in diagnostics:
                if not isinstance(diagnostics[clock], list) or not diagnostics[clock]:
                    raise ValueError('Invalid optional constructor diagnostic')
                for value in diagnostics[clock]:
                    _integer(value, clock, 0, (1 << 63)-1)

        observed = validate_scope_observations(diagnostics.get('scope_observations'), key[1])
        if 'native_compilation_accounting_raw_ns' in diagnostics:
            raw = _integer(diagnostics['native_compilation_accounting_raw_ns'],
                           'native compilation accounting', 0, (1 << 63)-1)
            compilation = observed.get('native_compilation', {})
            if (key[1] == 'reference' or len(compilation) != 1 or
                    raw != next(iter(compilation.values()))['accounting_raw_ns']):
                raise ValueError('Contradictory native compilation accounting')

        for clock in ('cpu_ns', 'wall_ns'):
            # Owner windows include driver/oracle work and cannot be shorter than their actual calls.
            if max(value[clock] for value in observed['owner_window'].values()) < sum(
                    sample[clock] for sample in parsed['invocation']['samples']):
                raise ValueError('Owner diagnostic does not encompass its full calls')

        _policy(parsed, key[1])
        binary = _command(row.get('run'), files)
        image_key = (case['family'], 'reference' if key[1] == 'reference' else 'production')
        if image_key in images and images[image_key] != binary:
            raise ValueError('Matched family uses different executable images')
        images[image_key] = binary
        role_orders.setdefault((key[0], key[2]), []).append(key[1])
    if seen != expected or any(tuple(roles) != ORDERS[order] for (_, order), roles in role_orders.items()):
        raise ValueError('Incomplete or foreign process role order')
    families = {case['family'] for case in inventory}
    for family in families:
        if files[images[family, 'production']] == files[images[family, 'reference']]:
            raise ValueError('Reference cannot reuse the independent production image')
    builds = report.get('builds')
    if not isinstance(builds, list):
        raise ValueError('Missing current production builds')
    for family in families:
        selected = [row for row in builds if row.get('family') == family]
        if len(selected) != 1:
            raise ValueError('Missing or duplicate matched family build')
        build = selected[0]
        binary = images[family, 'production']
        if (build.get('binary') != binary or build.get('binary_sha256') != files[binary] or
                build.get('defines') != identity['native_build_defines']+
                ([] if family == 'synthetic' else ['pvmArm64JitOwnerReceipt'])):
            raise ValueError('Production build identity/profile disagreement')
        record = _mapping(build.get('run'), 'production build result')
        if type(record.get('exit_code')) is not int or record['exit_code'] != 0:
            raise ValueError('Failed production build')
    covered = set()
    controls = report.get('controls')
    if not isinstance(controls, list):
        raise ValueError('Missing positive/refusal controls')
    for row in controls:
        row = _mapping(row, 'control')
        _text(row.get('case_id'), 'control case ID')
        ids = [key for key, case in cases.items() if case['family'] == 'synthetic'] if (
            row.get('case_id') == 'synthetic') else [row.get('case_id')]
        role, kind = row.get('role'), row.get('kind')
        if not ids or role not in ROLES or kind not in ('positive', 'assertions', 'state', 'events'):
            raise ValueError('Foreign control identity')
        binary = _command(row.get('run'), files, kind == 'positive')
        for case_id in ids:
            if case_id not in cases or (kind == 'events' and cases[case_id]['family'] != 'doom'):
                raise ValueError('Foreign control case')
            key = (case_id, role, kind)
            image_key = (cases[case_id]['family'], 'reference' if role == 'reference' else 'production')
            if key in covered or images[image_key] != binary:
                raise ValueError('Duplicate or foreign control image')
            covered.add(key)
    required = {(key, role, kind) for key, case in cases.items() for role in ROLES
                for kind in (('positive', 'assertions', 'state', 'events') if case['family'] == 'doom'
                             else ('positive', 'assertions', 'state'))}
    if covered != required:
        raise ValueError('Incomplete positive/refusal control matrix')
    return report


def _rows(report):
    """Index validated process cells without trusting cached derived medians or ratios."""
    return {(r['case_id'], r['role'], r['order']): r['parsed'] for r in report['runs']}


@schema_reader
def statistics_rows(report):
    """Expose raw-derived order/clock/phase observations for renderers and numeric consumers."""
    validate_report(report)
    rows, result = _rows(report), []
    for phase in ('cold', 'reused'):
        for case in case_inventory(report['scope']):
            for order in (0, 1):
                for clock in ('cpu_ns', 'wall_ns'):
                    values = {}
                    for role in ROLES:
                        samples = rows[case['case_id'], role, order]['invocation']['samples']
                        values[role] = samples[0][clock] if phase == 'cold' else statistics.median(
                            sample[clock] for sample in samples[3:13])
                    result.append(dict(case_id=case['case_id'], order=order, clock=clock,
                        phase=phase, **values, interpreted_over_reference=
                        values['interpreted']/values['reference'],
                        jit_over_reference=values['jit']/values['reference']))
    return result


@schema_reader
def cumulative_rows(report):
    """Sum every public-call prefix exactly; observed crossovers make no future reuse prediction."""
    validate_report(report)
    rows, result = _rows(report), []
    for case in case_inventory(report['scope']):
        for order in (0, 1):
            for clock in ('cpu_ns', 'wall_ns'):
                # Each process/clock owns thirteen independent integer prefixes, including samples1/2.
                totals, prefixes = dict.fromkeys(ROLES, 0), []
                for sample in range(13):
                    for role in ROLES:
                        totals[role] += rows[case['case_id'], role, order]['invocation'][
                            'samples'][sample][clock]
                    prefixes.append(dict(call_count=sample+1, **totals,
                        jit_minus_interpreted_ns=totals['jit']-totals['interpreted'],
                        jit_over_interpreted=totals['jit']/totals['interpreted'],
                        interpreted_over_reference=totals['interpreted']/totals['reference'],
                        jit_over_reference=totals['jit']/totals['reference']))
                # A delayed spike can undo a crossing; retain the first and the observed lasting one.
                first, through_final = None, None
                for index, prefix in enumerate(prefixes):
                    if prefix['jit_minus_interpreted_ns'] <= 0:
                        if first is None: first = prefix['call_count']
                        if (through_final is None and all(
                                p['jit_minus_interpreted_ns'] <= 0 for p in prefixes[index:])):
                            through_final = prefix['call_count']
                result.append(dict(case_id=case['case_id'], order=order, clock=clock,
                    prefixes=prefixes, first_break_even_call_count=first,
                    first_break_even_holds_through_final=(
                        through_final == first if first is not None else None),
                    break_even_through_final_from_call_count=through_final))
    return result


@schema_reader
def render_summary(report):
    """Render call windows, cumulative costs and observed crossovers with separate constructor scope."""
    validate_report(report)
    rows = _rows(report)
    observations = statistics_rows(report)
    lines = ['# PVM full-invocation performance ('+report['architecture']+')', '',
             'Source `'+report['revision']+'`; cohort full-invocation-v1 / '+CODE_LIFETIME+'.',
             'Cold sample0 encloses code admission, runtime startup, restoration, execution and output publication. '
             'Resident samples1–12 include restoration and output collection/publication. '
             'Final RAM is consumed before reuse; no artificial reference RAM freeze is added.',
             'Primary process CPU includes all in-process threads; wall is elapsed time. '
             'Fixture IO and independent state/event oracle scans are outside each call.',
             'Thirteen raw calls; reused statistics use samples3–12, without native-readiness filtering. '
             'Each process order is separate. Ratios compare only this native runner.', '']
    for phase in ('cold', 'reused'):
        lines += [phase.capitalize()+' public call', '',
                  '| Case | Order | Clock | Interpreted ms | JIT ms | Reference ms | I/ref | J/ref |',
                  '|---|---:|---|---:|---:|---:|---:|---:|']
        for observation in observations:
            if observation['phase'] == phase:
                values = [observation[role] for role in ROLES]
                lines.append('| '+observation['case_id']+' | '+str(observation['order'])+' | '+
                    observation['clock'][:-3]+' | '+' | '.join(f'{v/1e6:.6f}' for v in values)+
                    f' | {observation["interpreted_over_reference"]:.6f} | '+
                    f'{observation["jit_over_reference"]:.6f} |')
        lines.append('')
    lines += ['Sum of thirteen full-call windows (samples0–12)', '',
              'This sums actual enclosing windows, not owner-lifetime CPU/wall: asynchronous work can run between calls. '
              'Break-even counts are calls, including the cold call; reuses are calls minus one. '
              'JIT <= interpreted is break-even. A first crossing can reverse. '
              'Holding through call13 describes only this observed window, without a future prediction.', '',
              '| Case | Order | Clock | Interpreted total ms | JIT total ms | Reference total ms | J/I | I/ref | J/ref | First break-even call | Holds through13 | Break-even from call through13 |',
              '|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|---:|']
    for observation in cumulative_rows(report):
        total = observation['prefixes'][-1]
        first = observation['first_break_even_call_count']
        through = observation['break_even_through_final_from_call_count']
        holds = observation['first_break_even_holds_through_final']
        # Missing crossovers stay absent observations; no extrapolated reuse count fills the gap.
        lines.append('| '+observation['case_id']+' | '+str(observation['order'])+' | '+
            observation['clock'][:-3]+' | '+
            ' | '.join(f'{total[role]/1e6:.6f}' for role in ROLES)+' | '+
            ' | '.join(f'{total[key]:.6f}' for key in ('jit_over_interpreted',
                'interpreted_over_reference', 'jit_over_reference'))+' | '+
            (str(first) if first is not None else 'not observed')+' | '+
            ('not observed' if holds is None else 'yes' if holds else 'no')+' | '+
            (str(through) if through is not None else 'not observed')+' |')
    lines.append('')
    lines += ['Actual JIT policy and owner work', '',
              'Readiness and native coverage are observations. Checked fallback and zero native operations '
              'remain valid; no wait, rehearsal, minimum count or sample filtering is introduced. '
              'Native compilation accounting fields are not worker/process clocks.', '',
              '| Case | Order | Actual | Fragments | Calls | Operations | Code bytes |',
              '|---|---:|---|---:|---:|---:|---:|']
    for case in case_inventory(report['scope']):
        for order in (0, 1):
            parsed = rows[case['case_id'], 'jit', order]
            native, policy = parsed['native'], parsed['policy']
            lines.append(f'| {case["case_id"]} | {order} | {policy["actual"]} | '+
                ' | '.join(str(native.get(key, 0)) for key in ('fragments', 'calls', 'operations', 'code_bytes'))+' |')
    lines += ['', 'Optional constructor/runtime/lifecycle diagnostics remain in the raw report. '
              'They are not added to or subtracted from the primary enclosing clocks. '
              'Unavailable subsidiary clocks remain absent.', '']
    return '\n'.join(lines)+'\n'


@schema_reader
def render_samples_csv(report):
    """Retain actual calls and restoration/cache receipts without spreading one-time work over samples."""
    validate_report(report)
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n')
    writer.writerow(('revision', 'architecture', 'scope', 'measurement_boundary', 'output_contract',
                     'cpu_clock', 'case_id', 'role', 'order', 'sample', 'cold', 'reused',
                     'cpu_ns', 'wall_ns', 'reference_cache_before_reset_bytes',
                     'reference_cache_after_reset_bytes', 'reference_cache_after_run_bytes'))
    for row in report['runs']:
        invocation = row['parsed']['invocation']
        for sample in invocation['samples']:
            index = sample['sample']
            instance = (invocation['reference_instance']['samples'][index]
                        if row['role'] == 'reference' else None)
            extra = tuple(instance[key] for key in ('before_reset_bytes', 'after_reset_bytes',
                'after_run_bytes')) if instance else ('',)*3
            writer.writerow((report['revision'], report['architecture'], report['scope'],
                'full-invocation-v1', 'consume-before-reuse-v1', 'process-cpu', row['case_id'],
                row['role'], row['order'], index, int(index == 0), int(index >= 3),
                sample['cpu_ns'], sample['wall_ns'], *extra))
    return output.getvalue()


def _atomic_text(path, text):
    """Replace one complete UTF-8 artifact; a partial write never becomes the report commit marker."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                         prefix='.'+path.name+'-', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        # Failed replacement must not leave a misleading staged artifact for later discovery.
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def _retire_tables(folder):
    """Remove only owned success views before publishing a new attempt or failed result."""
    for name in ('summary.md', 'samples.csv'):
        (folder/name).unlink(missing_ok=True)


def publish_report(report, folder):
    """Validate/render a final candidate before passed publication; failures retire every old green view."""
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    candidate = copy.deepcopy(report)
    _retire_tables(folder)
    # Invalidate the old commit marker before validation or rendering can fail.
    (folder/'results.json').unlink(missing_ok=True)
    try:
        if candidate.get('status') == 'failed':
            _atomic_text(folder/'results.json', json.dumps(candidate, indent=2, allow_nan=False)+'\n')
            return candidate
        if candidate.get('status') not in ('incomplete', 'passed'):
            raise ValueError('Unknown final performance publication state')
        candidate['status'] = 'passed'
        validate_report(candidate)
        summary, samples = render_summary(candidate), render_samples_csv(candidate)
        encoded = json.dumps(candidate, indent=2, allow_nan=False)+'\n'
        _atomic_text(folder/'samples.csv', samples)
        _atomic_text(folder/'summary.md', summary)
        _atomic_text(folder/'results.json', encoded)
        return candidate
    except BaseException as error:
        # No rendering/write/validation interruption may expose a green table beside failed evidence.
        _retire_tables(folder)
        candidate.update(status='failed', error=str(error))
        try:
            _atomic_text(folder/'results.json', json.dumps(candidate, indent=2, allow_nan=False)+'\n')
        except (TypeError, ValueError):
            # Malformed untrusted extras are not allowed to prevent a minimal truthful failure record.
            _atomic_text(folder/'results.json', json.dumps(dict(schema=SCHEMA, status='failed',
                         error=str(error)))+'\n')
        raise
