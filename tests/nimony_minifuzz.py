# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run unmodified upstream minifuzz against actual application processes and independent GP0.8 effect maps."""
import hashlib
import os
from pathlib import Path
import signal
import struct
import subprocess
import tempfile
import time
from jam_minifuzz_trace import exchanges, IMPORT_OUTCOMES
from jam_minifuzz_replay import replay
from nimony_fuzz_guests import prepare_effect_sessions, import_counts
from current_stf_trace_command_oracle import chain_config


def local_missing_evidence(endpoint, case):
    """Real metadata without the required child root closes locally after an exact unchanged seed-state query."""
    from nimony_fuzz import connect, exchange
    from state_layout_oracle import digest
    with connect(endpoint, features=3) as peer:
        assert exchange(peer, case['initialize']) == b'\x02'+case['state'][:32]
        assert exchange(peer, b'\x04'+digest(case['header'])) == b'\x05'+case['state'][32:]
        payload = b'\x03'+case['block']
        peer.sendall(struct.pack('<I', len(payload))+payload)
        assert peer.recv(1) == b'' # No fabricated consensus Error substitutes for missing local ancestry evidence.


def exercise_profile(binary, policy_binary, script, environment, run, planned, parameters):
    """Own one target under one declared immutable host profile; every expected pair precedes its startup."""
    assert planned and all(job['parameters'] == parameters for job, _ in planned)
    spec = planned[0][0].get('spec', 'tiny')
    assert spec in ('tiny', 'full') and all(job.get('spec', 'tiny') == spec for job, _ in planned)
    results = []
    observed_references = {}
    local_controls = 0
    stream_recoveries = 0
    fork_evictions = 0
    run.mkdir(parents=True)
    log_path = run/'target.log'
    with tempfile.TemporaryDirectory(prefix='jam-minifuzz-target-') as selected:
        directory = Path(selected)
        directory.chmod(0o700)
        endpoint = directory/'target.sock'
        policy = directory/'policy.txt'
        configured = directory/'parameters.json'
        subprocess.run([str(policy_binary), str(policy)]+(['full'] if spec == 'full' else []), check=True, timeout=30)
        job = planned[0][0]
        config = chain_config(job['header']+job['state'], parameters)
        configured.write_text(config)
        target_env = {key:value for key,value in os.environ.items() if not key.startswith('JAM_FUZZ')}
        target_env.update(JAM_FUZZ='1', JAM_FUZZ_SPEC=spec, JAM_FUZZ_DATA_PATH=str(directory),
                          JAM_FUZZ_SOCK_PATH=str(endpoint), JAM_FUZZ_LOG_LEVEL='error')
        with log_path.open('wb') as log:
            process = subprocess.Popen([str(binary), 'serve-fuzz', '--fuzz-policy', str(policy), '--fuzz-parameters', str(configured), '--fuzz-state-writes', '1000', '--fuzz-state-write-bytes', '4194304' if spec == 'full' else '1000000'],
                                       env=target_env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic()+30
                while not endpoint.exists():
                    assert process.poll() is None, 'Target exited before minifuzz startup'
                    assert time.monotonic() < deadline, 'Minifuzz target startup deadline'
                    time.sleep(0.01)
                # Each declared local refusal runs against the same owned target before complete valid replays.
                for job, _ in planned:
                    for case in job.get('local_missing_evidence', ()):
                        local_missing_evidence(endpoint, case)
                        local_controls += 1
                # Source-owned recovery cases retain their independent packet/map plan and exact observed count.
                for job, _ in planned:
                    if 'stream_recovery' in job:
                        from jam_fuzzer_stream_recovery import exercise as recover_stream
                        stream_recoveries += recover_stream(endpoint, job['stream_recovery'])
                # Finite sibling retention is observed through the actual protocol, including local unknown-state closure.
                for job, _ in planned:
                    if 'fork_retention' in job:
                        from jam_fuzzer_fork_retention import exercise as exercise_forks
                        fork_evictions += exercise_forks(endpoint, job['fork_retention'])
                for index, (job, pairs) in enumerate(planned):
                    result = replay(script, environment, endpoint, run/f'case-{index:04d}', pairs, spec=spec)
                    results.append(result)
                    assert result['passed'], result['failure']
                    observed = observed_references.setdefault(job['reference'],dict.fromkeys(IMPORT_OUTCOMES,0))
                    declared = import_counts([job])
                    # Count only actual matching replies from positive sessions, independently for every source owner.
                    for field in IMPORT_OUTCOMES:
                        assert result[field] == declared[field]
                        observed[field] += result[field]
                negative = replay(script, environment, endpoint, run/'false-success', planned[0][1], corrupt_last=True, spec=spec)
                assert not negative['passed'] and negative['upstream_exit_code'] == 0
                assert negative['failure'].startswith('Unexpected target response')
                assert negative['completed_exchanges'] == len(planned[0][1])
                assert 'Unexpected target response' in (run/'false-success/upstream.log').read_text()
                process.send_signal(signal.SIGTERM)
                assert process.wait(timeout=30) == 0
                assert not endpoint.exists()
                assert configured.read_text() == config
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10) # Failure/deadline cleanup targets only the process owned by this profile.
    return dict(passed=True, **{field:sum(row[field] for row in results) for field in IMPORT_OUTCOMES},
                observed_references=[dict(reference=name,**counts) for name,counts in sorted(observed_references.items())],
                completed_sessions=len(results), local_missing_evidence=local_controls, stream_recoveries=stream_recoveries, fork_evictions=fork_evictions,
                completed_exchanges=sum(result['completed_exchanges'] for result in results),
                parameters_sha256=hashlib.sha256(parameters).hexdigest(), spec=spec, false_success_control=True,
                log=str(log_path))


def exercise(binary, policy_binary, script, environment, folder):
    """Freeze all complete maps first, then require strict upstream interoperability for every explicit profile."""
    jobs, evidence = prepare_effect_sessions()
    return exercise_plan(binary, policy_binary, script, environment, folder, jobs, evidence)


def exercise_plan(binary, policy_binary, script, environment, folder, jobs, evidence):
    """Execute a complete independently declared plan; scoped callers retain identical strict process/profile checks."""
    assert evidence['sessions'] == len(jobs) and jobs
    assert evidence['signed_imports'] == sum(len(job['steps']) for job in jobs)
    assert all(evidence[field] == count for field,count in import_counts(jobs).items())
    local_controls = sum(len(job.get('local_missing_evidence', ())) for job in jobs)
    assert evidence['expected_local_missing_evidence'] == local_controls
    stream_controls = sum(len(job['stream_recovery']['cases'])+1 for job in jobs if 'stream_recovery' in job)
    assert evidence['expected_stream_recoveries'] == stream_controls
    fork_controls = sum(2 for job in jobs if 'fork_retention' in job)
    assert evidence['expected_fork_evictions'] == fork_controls
    planned = [(job, exchanges(job)) for job in jobs]
    profiles = tuple(dict.fromkeys(job['parameters'] for job in jobs))
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='minifuzz-', dir=folder))
    results = []
    for index, parameters in enumerate(profiles):
        selected = [(job, pairs) for job, pairs in planned if job['parameters'] == parameters]
        results.append(exercise_profile(binary, policy_binary, script, environment,
                                       run/f'profile-{index:02d}', selected, parameters))
    observed_references = {}
    # Profile allocation may split a reference; aggregate only the observed positive-session replies.
    for profile in results:
        for row in profile['observed_references']:
            observed = observed_references.setdefault(row['reference'],dict.fromkeys(IMPORT_OUTCOMES,0))
            for field in IMPORT_OUTCOMES: observed[field] += row[field]
    counts = {'planned_'+field:evidence[field] for field in IMPORT_OUTCOMES}
    counts.update({'completed_'+field:sum(row[field] for row in results) for field in IMPORT_OUTCOMES})
    assert all(counts['planned_'+field] == counts['completed_'+field] for field in IMPORT_OUTCOMES)
    return dict(passed=True, **counts,
                observed_references=[dict(reference=name,**counts) for name,counts in sorted(observed_references.items())],
                planned_sessions=len(planned),
                planned_fork_evictions=fork_controls,
                completed_fork_evictions=sum(row['fork_evictions'] for row in results),
                planned_stream_recoveries=stream_controls,
                completed_stream_recoveries=sum(row['stream_recoveries'] for row in results),
                planned_local_missing_evidence=local_controls,
                completed_local_missing_evidence=sum(row['local_missing_evidence'] for row in results),
                completed_sessions=sum(result['completed_sessions'] for result in results),
                planned_exchanges=sum(len(pairs) for _, pairs in planned),
                completed_exchanges=sum(result['completed_exchanges'] for result in results),
                signed_imports=evidence['signed_imports'], independent_references=evidence['references'],
                planned_host_profiles=len(profiles), completed_host_profiles=len(results),
                host_profiles=results, false_success_control=all(result['false_success_control'] for result in results),
                upstream_script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(), artifacts=str(run),
                scope='unmodified pinned upstream minifuzz; independently calculated GP0.8 complex-effect whole maps; no generated campaign')
