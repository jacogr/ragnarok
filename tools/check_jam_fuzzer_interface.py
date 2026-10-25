#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run the current JAM fuzz interface's fixed independent corpora and real-entry socket checks.

This opt-in CI group validates the engine interface, not a generated campaign. A compatible
polkajam-fuzz engine remains a separate prerequisite. Make owns all dependency setup.
"""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys
import time
from types import SimpleNamespace
from native_checks import NativeChecks, ROOT, announce
from runtime_provenance import runtime_sources
from setup_nimony import installed
from corpus_state import CORPORA

BUILD = ROOT/'build/tests/jam-fuzzer-interface'
# Source-owned corpus declarations supply identities; the feature prefix selects this opt-in scope.
CASES = tuple(sorted(name for name in CORPORA.tasks if name.startswith('jam_fuzzer_')))


def corpus_verified(result):
    """Require successful native construction/execution and the exact independently expected transcript hash."""
    if not isinstance(result, dict) or result.get('passed') is not True:
        return False
    expected = result.get('expected_sha256')
    if not isinstance(expected, str) or len(expected) != 64 or any(char not in '0123456789abcdef' for char in expected):
        return False
    for stage in ('build', 'run'):
        observed = result.get(stage)
        if not isinstance(observed, dict) or type(observed.get('exit_code')) is not int or observed['exit_code'] != 0:
            return False
    return result.get('actual_sha256') == expected


def guest_socket_verified(result):
    """Compare observed real socket work with its independently prepared full-map plan; incomplete loops cannot pass."""
    if not isinstance(result, dict) or result.get('passed') is not True:
        return False
    counts = ('sessions', 'signed_imports', 'guest_siblings', 'expected_state_queries',
              'completed_sessions', 'completed_imports', 'retained_siblings',
              'complete_state_queries', 'consensus_rejections', 'isolated_reconnects')
    if any(type(result.get(name)) is not int or result[name] <= 0 for name in counts):
        return False
    return (result['completed_sessions'] == result['sessions']
            and result['completed_imports'] == result['signed_imports']
            and result['retained_siblings'] == result['guest_siblings']
            and result['complete_state_queries'] == result['expected_state_queries']
            and result['consensus_rejections'] == result['signed_imports'])


def import_evidence_verified(result, declared, profiles):
    """Require source-owned outcome budgets, actual per-reference observations and exact per-profile/global totals."""
    from jam_minifuzz_trace import IMPORT_OUTCOMES
    expected = {row['reference']:{field:row[field] for field in IMPORT_OUTCOMES} for row in declared}
    def observations(rows):
        """Reject missing, duplicated, foreign or ill-typed observed owners before summing their actual outcomes."""
        if not isinstance(rows,list): return None
        found = {}
        for row in rows:
            if not isinstance(row,dict): return None
            name = row.get('reference')
            if not isinstance(name,str) or name not in expected or name in found: return None
            if any(type(row.get(field)) is not int or row[field] < 0 for field in IMPORT_OUTCOMES): return None
            found[name] = {field:row[field] for field in IMPORT_OUTCOMES}
        return found
    actual = observations(result.get('observed_references'))
    if actual != expected: return False
    combined = {}
    for profile in profiles:
        if not isinstance(profile,dict): return False
        observed = observations(profile.get('observed_references'))
        if observed is None: return False
        for field in IMPORT_OUTCOMES:
            if type(profile.get(field)) is not int or profile[field] < 0: return False
            if profile[field] != sum(row[field] for row in observed.values()): return False
        for name,row in observed.items():
            counts = combined.setdefault(name,dict.fromkeys(IMPORT_OUTCOMES,0))
            for field in IMPORT_OUTCOMES: counts[field] += row[field]
    if combined != expected: return False
    for field in IMPORT_OUTCOMES:
        total = sum(row[field] for row in declared)
        if any(type(result.get(prefix+field)) is not int or result[prefix+field] != total
               for prefix in ('planned_','completed_')): return False
        if sum(row[field] for row in profiles) != total: return False
    return sum(result['completed_'+field] for field in IMPORT_OUTCOMES) == result['signed_imports']


def minifuzz_verified(result):
    """Require all upstream exchanges and an observed false-success control, not the upstream process status alone."""
    if not isinstance(result, dict) or result.get('passed') is not True or result.get('false_success_control') is not True:
        return False
    counts = ('planned_sessions', 'completed_sessions', 'planned_exchanges', 'completed_exchanges', 'signed_imports')
    if any(type(result.get(name)) is not int or result[name] <= 0 for name in counts):
        return False
    from jam_minifuzz_plan import expectations, CONTROL_FIELDS
    try:
        declared = expectations()
    except (AssertionError,OSError,ValueError):
        return False # Changed fixture pins cannot become a weaker expected CI plan.
    references = result.get('independent_references')
    if not isinstance(references,list) or len(references) != len(declared):
        return False
    actual = {}
    for row in references:
        if not isinstance(row,dict) or not isinstance(row.get('reference'),str) or row['reference'] in actual:
            return False
        actual[row['reference']] = row
    if set(actual) != {row['reference'] for row in declared}:
        return False
    for expected in declared:
        row = actual[expected['reference']]
        if any(row.get(key) != expected[key] for key in ('fixture_sha256','sessions','signed_imports','accepted_imports','refused_imports')):
            return False
        if any(type(row.get(key)) is not int for key in ('sessions','signed_imports','accepted_imports','refused_imports')):
            return False
        stream = row.get('expected_sha256')
        if not isinstance(stream,str) or len(stream) != 64 or any(char not in '0123456789abcdef' for char in stream):
            return False
        if expected['expected_sha256'] is not None and stream != expected['expected_sha256']:
            return False
    if (result['planned_sessions'] != sum(row['sessions'] for row in declared)
            or result['signed_imports'] != sum(row['signed_imports'] for row in declared)
            or result['planned_exchanges'] != sum(row['exchanges'] for row in declared)):
        return False
    for field in CONTROL_FIELDS:
        if result.get('planned_'+field) != sum(row['controls'][field] for row in declared):
            return False
    profiles = result.get('host_profiles')
    if not isinstance(profiles, list) or not profiles:
        return False
    if (type(result.get('planned_host_profiles')) is not int
            or type(result.get('completed_host_profiles')) is not int
            or result['planned_host_profiles'] != len(profiles)
            or result['completed_host_profiles'] != len(profiles)):
        return False
    # Every independently declared local control requires exact nonnegative per-profile and aggregate completion.
    for planned,completed,field in (('planned_local_missing_evidence','completed_local_missing_evidence','local_missing_evidence'),
                                    ('planned_stream_recoveries','completed_stream_recoveries','stream_recoveries'),
                                    ('planned_fork_evictions','completed_fork_evictions','fork_evictions')):
        if any(type(result.get(key)) is not int or result[key] < 0 for key in (planned,completed)):
            return False
        if any(not isinstance(profile,dict) or type(profile.get(field)) is not int or profile[field] < 0 for profile in profiles):
            return False
        if result[planned] != result[completed] or result[completed] != sum(profile[field] for profile in profiles):
            return False
    if not import_evidence_verified(result,declared,profiles): return False
    identities = []
    for profile in profiles:
        if (not isinstance(profile, dict) or profile.get('passed') is not True
                or profile.get('false_success_control') is not True
                or any(type(profile.get(key)) is not int or profile[key] <= 0
                       for key in ('completed_sessions', 'completed_exchanges'))):
            return False
        identity = profile.get('parameters_sha256')
        if not isinstance(identity, str) or len(identity) != 64 or any(c not in '0123456789abcdef' for c in identity):
            return False
        identities.append(identity)
    return (len(set(identities)) == len(identities)
            and result['planned_sessions'] == result['completed_sessions'] == sum(row['completed_sessions'] for row in profiles)
            and result['planned_exchanges'] == result['completed_exchanges'] == sum(row['completed_exchanges'] for row in profiles))



def passed(report):
    """Require every declared transcript plus complete real-entry guest execution, never a success flag alone."""
    cases = report.get('cases', {})
    socket = report.get('socket', {})
    return (bool(CASES) and set(cases) == set(CASES)
            and all(corpus_verified(cases[name]) for name in CASES)
            and socket.get('passed') is True and guest_socket_verified(socket.get('guests'))
            and minifuzz_verified(report.get('minifuzz')))


def summary(report):
    """Distinguish actual interface verdicts from unavailable live generated campaign validation."""
    lines = ['# JAM fuzzer interface', '',
             'Interface checks: '+('passed' if passed(report) else 'failed'), '',
             'Live generated campaign validation: pending compatible polkajam-fuzz engine.', '',
             '| Check | Result |', '| --- | --- |']
    for name in CASES:
        result = report.get('cases', {}).get(name)
        lines.append('| '+name+' | '+('passed' if corpus_verified(result) else 'failed or missing')+' |')
    lines.append('| real-entry socket | '+('passed' if report.get('socket', {}).get('passed') else 'failed or missing')+' |')
    lines.append('| upstream minifuzz whole-map replay | '+('passed' if minifuzz_verified(report.get('minifuzz')) else 'failed or missing')+' |')
    upstream = report.get('minifuzz')
    if minifuzz_verified(upstream):
        lines.extend(['', 'Declared whole-map references: '+str(len(upstream['independent_references']))+'.',
                      'Upstream sessions: '+str(upstream['completed_sessions'])+'/'+str(upstream['planned_sessions'])+'.',
                      'Observed accepted / refused imports: '+str(upstream['completed_accepted_imports'])+' / '+str(upstream['completed_refused_imports'])+'.',
                      'Exact upstream exchanges: '+str(upstream['completed_exchanges'])+'/'+str(upstream['planned_exchanges'])+'.',
                      'Local missing evidence / stream recovery / fork retention: '+str(upstream['completed_local_missing_evidence'])+' / '+str(upstream['completed_stream_recoveries'])+' / '+str(upstream['completed_fork_evictions'])+'.'])
    guests = report.get('socket', {}).get('guests')
    if guest_socket_verified(guests):
        lines.extend(['', 'Nonempty guest socket imports: '+str(guests['completed_imports'])+'/'+str(guests['signed_imports'])+'.',
                      'Complete guest state queries: '+str(guests['complete_state_queries'])+'/'+str(guests['expected_state_queries'])+'.',
                      'Guest sibling retention and fresh-session isolation: passed.'])
    else:
        lines.extend(['', 'Nonempty guest socket evidence: failed or missing.'])
    return '\n'.join(lines)+'\n'


def main():
    """Provision independent native owners, execute registered cases sequentially and retain fresh failure evidence."""
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    (BUILD/'summary.md').unlink(missing_ok=True)
    started = time.monotonic()
    report = dict(status='failed', cases={}, engine_validation='pending',
                  scope='fixed current-profile interface cases; no generated campaign',
                  environment=dict(system=platform.system(), machine=platform.machine()))
    try:
        compiler, _ = installed()
        checks = NativeChecks(BUILD, reuse_builds=True)
        report['compiler'] = checks.command([compiler, '--version'], 'compiler')
        report['revision'] = checks.command(['git', 'rev-parse', 'HEAD'], 'revision')['output'].strip()
        report['sources'] = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                             for path in runtime_sources()}
        sys.path.insert(0, str(ROOT/'tests'))
        from nimony_crypto import prepare as prepare_crypto
        from bandersnatch_native import prepare as prepare_bandersnatch
        from nimony_quic import prepare as prepare_quic
        import e2e_checks
        crypto, _, report['crypto_native'] = prepare_crypto(BUILD)
        bs, _, report['bandersnatch_native'] = prepare_bandersnatch(BUILD)
        quic, _, report['quic_native'] = prepare_quic()
        libraries = dict(crypto=crypto, bandersnatch=bs, quic=quic)
        for name in CASES:
            # These are the registered independent references; native results never calculate expected maps.
            report['cases'][name] = CORPORA.tasks[name](compiler, report, checks, libraries)
            if not report['cases'][name]['passed']:
                raise AssertionError('Failed interface corpus: '+name)
        context = SimpleNamespace(compiler=compiler, checks=checks, report=report, crypto=crypto, bs=bs, quic=quic)
        e2e_checks.prepare_peer(context)
        e2e_checks.prepare_fuzzer_policy(context)
        report['socket'] = e2e_checks.application_fuzzer_interface(context)
        e2e_checks.prepare_minifuzz(context)
        report['minifuzz'] = e2e_checks.application_minifuzz_interface(context)
        report['status'] = 'checks-passed' if passed(report) else 'failed'
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        # A partial invocation cannot reuse another group's success or an earlier results file.
        report['failure'] = repr(error)
    finally:
        report['elapsed_seconds'] = round(time.monotonic()-started, 6)
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        (BUILD/'summary.md').write_text(summary(report))
    success = report['status'] == 'checks-passed' and passed(report)
    announce('JAM fuzzer interface verification', success)
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
