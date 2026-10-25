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


def minifuzz_verified(result):
    """Require all upstream exchanges and an observed false-success control, not the upstream process status alone."""
    if not isinstance(result, dict) or result.get('passed') is not True or result.get('false_success_control') is not True:
        return False
    counts = ('planned_sessions', 'completed_sessions', 'planned_exchanges', 'completed_exchanges', 'signed_imports')
    if any(type(result.get(name)) is not int or result[name] <= 0 for name in counts):
        return False
    profiles = result.get('host_profiles')
    if not isinstance(profiles, list) or not profiles:
        return False
    if (type(result.get('planned_host_profiles')) is not int
            or type(result.get('completed_host_profiles')) is not int
            or result['planned_host_profiles'] != len(profiles)
            or result['completed_host_profiles'] != len(profiles)):
        return False
    local_counts = ('planned_local_missing_evidence', 'completed_local_missing_evidence')
    if any(type(result.get(key)) is not int or result[key] < 0 for key in local_counts):
        return False
    if any(not isinstance(profile, dict) or type(profile.get('local_missing_evidence')) is not int or profile['local_missing_evidence'] < 0 for profile in profiles):
        return False
    if result[local_counts[0]] != result[local_counts[1]] or result[local_counts[1]] != sum(profile['local_missing_evidence'] for profile in profiles):
        return False
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
