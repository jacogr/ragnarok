#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify issue215 target readiness; a pending engine can never become a live campaign pass."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
from native_checks import NativeChecks, ROOT, announce
from setup_nimony import installed
from runtime_provenance import runtime_sources
from check_jam_fuzzer_interface import corpus_verified
from jam_network_corpora import CORPORA

BUILD = ROOT/'build/tests/jam-network'


def complete(report):
    """Require the entire source-owned corpus and actual socket counts, without crediting engine availability."""
    cases = report.get('cases',{})
    if not CORPORA.tasks or not isinstance(cases,dict) or set(cases) != set(CORPORA.tasks) or not all(corpus_verified(row) for row in cases.values()):
        return False
    observed = report.get('socket',{})
    return (observed.get('passed') is True and observed.get('sessions') == 17
            and observed.get('completed_sessions') == 17 and observed.get('signed_imports') == 67
            and observed.get('completed_imports') == 67 and observed.get('consensus_rejections') == 67
            and observed.get('expected_state_queries') == 171 and observed.get('complete_state_queries') == 171
            and observed.get('isolated_reconnects') == 1 and observed.get('guest_siblings') == 3
            and observed.get('retained_siblings') == 3)


def socket_check(binary, folder):
    """Freeze independent messages first, then exercise environment-only startup and complete native STF."""
    from nimony_fuzz_guests import reference_sessions, session_evidence, exercise_sessions
    import jam_fuzzer_network_oracle as reference
    jobs, proof = reference_sessions(reference,'jam_fuzzer_network',[reference.parameters()]*17,spec='fuzz',fork_capacity=8)
    evidence = session_evidence(jobs,[proof])
    (folder/'plan.json').write_text(json.dumps(evidence,indent=2)+'\n')
    # A short private directory keeps Unix socket paths below the native103-byte limit on all supported hosts.
    with tempfile.TemporaryDirectory(prefix='jam-network-') as selected:
        directory = Path(selected); endpoint = directory/'target.sock'
        directory.chmod(0o777) # Reproduce the pinned upstream launcher's mount mode; native startup must make it private.
        environment = {key:value for key,value in os.environ.items() if not key.startswith(('JAM_FUZZ','RAGNAROK_FUZZ_'))}
        arguments = [str(binary)]
        environment.update(JAM_FUZZ='1',JAM_FUZZ_SPEC='fuzz',JAM_FUZZ_DATA_PATH=str(directory/'data/nested'),
            JAM_FUZZ_SOCK_PATH=str(endpoint),JAM_FUZZ_LOG_LEVEL='error')
        for variable in ('JAM_FUZZ_SPEC','JAM_FUZZ_DATA_PATH','JAM_FUZZ_SOCK_PATH'):
            # The upstream launch contract alone configures the actual binary; missing inputs must refuse before IO.
            missing = dict(environment); del missing[variable]
            rejected = subprocess.run(arguments,env=missing,capture_output=True,timeout=30)
            assert rejected.returncode == 2 and b'FUZZ_START_FAILED' in rejected.stderr
            assert not endpoint.exists()
        for extra in (['--fuzz'],['--unknown','x']):
            # Unknown command spellings fail at the public CLI boundary before fuzz startup.
            rejected = subprocess.run(arguments+extra,env=environment,capture_output=True,timeout=30)
            expected = ('Unknown command: '+extra[0]+'; use ragnarok --help').encode()
            assert rejected.returncode == 2 and rejected.stderr.strip() == expected
            assert not endpoint.exists()
        assert not (directory/'data').exists()
        version = subprocess.run([str(binary),'--version'],env=environment,capture_output=True,timeout=30)
        assert version.returncode == 0 and b'Ragnarok' in version.stdout # Version inspection remains available to external launchers.
        with (folder/'target.log').open('wb') as log:
            process = subprocess.Popen(arguments,env=environment,stdout=log,stderr=log)
            try:
                deadline = time.monotonic()+30
                while not endpoint.exists():
                    # Startup refusal, missing libraries and stalled listeners must all fail readiness.
                    assert process.poll() is None, 'Network fuzz target exited before readiness'
                    assert time.monotonic() < deadline, 'Network fuzz startup deadline'
                    time.sleep(0.01)
                assert directory.stat().st_mode & 0o777 == 0o700
                assert (directory/'data/nested').stat().st_mode & 0o777 == 0o700
                result = exercise_sessions(endpoint,jobs,evidence)
                process.send_signal(signal.SIGTERM)
                assert process.wait(timeout=30) == 0 and not endpoint.exists()
                return result
            finally:
                if process.poll() is None:
                    process.kill(); process.wait(timeout=10) # Retire only this invocation's owned child.


def summary(report):
    """Report target readiness and live campaign status separately, including partial/failing invocations."""
    return ('# JAM Network fuzz target\n\nTarget readiness: '+report['status']+
            '.\n\nLive generated campaign: **pending** compatible GP0.8 engine and upstream fuzz-spec launcher.\n\n'
            'Preset:85 cores,255 initial validators,60-slot epochs. Fixed independent checks cover67 imports, '
            'ordinary/skipped epochs and255-to252/6 activation, nonempty reports and guest siblings. This is not a live campaign verdict.\n'+
            ('\nFailure: '+report['failure']+'\n' if 'failure' in report else ''))


def main():
    """Make provisions dependencies; this standalone group retains fresh strict evidence even when prerequisites fail."""
    BUILD.mkdir(parents=True,exist_ok=True)
    report = dict(status='failed',cases={},engine_validation='pending',scope='fixed issue215 target readiness only')
    try:
        sys.path.insert(0,str(ROOT/'tests'))
        compiler,_ = installed(); checks = NativeChecks(BUILD,reuse_builds=True)
        from nimony_crypto import prepare as crypto_prepare
        from bandersnatch_native import prepare as bs_prepare
        from nimony_quic import prepare as quic_prepare
        crypto,_,report['crypto_native'] = crypto_prepare(BUILD)
        bs,_,report['bandersnatch_native'] = bs_prepare(BUILD)
        quic,_,report['quic_native'] = quic_prepare()
        libraries = dict(crypto=crypto,bandersnatch=bs,quic=quic)
        report['sources'] = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in runtime_sources()}
        for name in sorted(CORPORA.tasks):
            # The owning frozen reference determines every expected full map before native replay.
            report['cases'][name] = CORPORA.tasks[name](compiler,report,checks,libraries)
            assert corpus_verified(report['cases'][name]), 'Failed network corpus: '+name
        from e2e_checks import prepare_peer
        context = SimpleNamespace(compiler=compiler,checks=checks,report=report,crypto=crypto,bs=bs,quic=quic)
        prepare_peer(context)
        assert context.peer[0]['exit_code'] == 0, 'Native target build failed'
        report['socket'] = socket_check(context.peer[1],BUILD)
        assert complete(report), 'Incomplete network target evidence'
        report['status'] = 'checks-passed'
    except (AssertionError,OSError,ValueError,subprocess.SubprocessError) as error:
        report['failure'] = repr(error)
    finally:
        (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
        (BUILD/'summary.md').write_text(summary(report))
    passed = report['status'] == 'checks-passed' and complete(report)
    announce('JAM Network target readiness (live engine pending)',passed)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
