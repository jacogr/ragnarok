# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run unmodified upstream minifuzz against the actual application and independent GP0.8 whole maps."""
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
from jam_fuzzer_guest_reference import host_parameters
from jam_minifuzz_trace import exchanges
from jam_minifuzz_replay import replay
from nimony_fuzz_guests import prepare_sessions
from current_stf_trace_command_oracle import chain_config


def exercise(binary, policy_binary, script, environment, folder):
    """Own both processes and sockets; retain upstream file-pair replay and strict independent exchange evidence."""
    jobs, evidence = prepare_sessions(host_parameters())
    planned = [exchanges(job) for job in jobs] # Every expected message precedes target startup or observed replies.
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='minifuzz-', dir=folder))
    results = []
    log_path = run/'target.log'
    with tempfile.TemporaryDirectory(prefix='jam-minifuzz-target-') as selected:
        directory = Path(selected)
        directory.chmod(0o700)
        endpoint = directory/'target.sock'
        policy = directory/'policy.txt'
        parameters = directory/'parameters.json'
        subprocess.run([str(policy_binary), str(policy)], check=True, timeout=30)
        config = chain_config(jobs[0]['header']+jobs[0]['state'], host_parameters())
        parameters.write_text(config)
        target_env = {key:value for key,value in os.environ.items() if not key.startswith('JAM_FUZZ')}
        target_env.update(JAM_FUZZ='1', JAM_FUZZ_SPEC='tiny', JAM_FUZZ_DATA_PATH=str(directory),
                          JAM_FUZZ_SOCK_PATH=str(endpoint), JAM_FUZZ_LOG_LEVEL='error')
        with log_path.open('wb') as log:
            process = subprocess.Popen([str(binary), 'serve-fuzz', str(policy), str(parameters), '1000', '1000000'],
                                       env=target_env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic()+30
                while not endpoint.exists():
                    assert process.poll() is None, 'Target exited before minifuzz startup'
                    assert time.monotonic() < deadline, 'Minifuzz target startup deadline'
                    time.sleep(0.01)
                for index, pairs in enumerate(planned):
                    result = replay(script, environment, endpoint, run/f'case-{index:04d}', pairs)
                    results.append(result)
                    assert result['passed'], result['failure']
                negative = replay(script, environment, endpoint, run/'false-success', planned[0], corrupt_last=True)
                assert not negative['passed'] and negative['upstream_exit_code'] == 0
                assert negative['failure'].startswith('Unexpected target response')
                assert negative['completed_exchanges'] == len(planned[0])
                assert 'Unexpected target response' in (run/'false-success/upstream.log').read_text() # Require a real decoded mismatch and exit0, not another early failure.
                process.send_signal(signal.SIGTERM)
                assert process.wait(timeout=30) == 0
                assert not endpoint.exists()
                assert parameters.read_text() == config
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=10) # Every failed comparison/deadline cleans only its exact owned target.
    return dict(passed=True, planned_sessions=len(planned), completed_sessions=len(results),
                planned_exchanges=sum(map(len, planned)), completed_exchanges=sum(result['completed_exchanges'] for result in results),
                signed_imports=evidence['signed_imports'], independent_references=evidence['references'],
                false_success_control=True, upstream_script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(),
                log=str(log_path), artifacts=str(run),
                scope='unmodified pinned upstream minifuzz replay; independent GP0.8 whole-map traces; no generated campaign')
