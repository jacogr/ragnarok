# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe the live download driver's OS resources at joined lifecycle barriers.

Exposes observe and growth; reuses the E2E OS observer without treating thread-local ARC as RSS.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import time
from test_quic_soak import resources, wait_marker

ROUNDS = 32
WARMUP = 8
RSS_LIMIT = 256 * 1024 * 1024
RSS_GROWTH = 16 * 1024 * 1024
DESCRIPTOR_GROWTH = 2


def growth(samples):
    """Require every lifecycle observation and apply existing soak budgets after fixed warmup."""
    if len(samples) != ROUNDS + 1:
        # Missing idle observations cannot stand in for joined native cleanup.
        raise ValueError('Need all 33 joined download resource observations')
    for sample in samples:
        # Idle barriers have already joined the sole preparation worker and closed native endpoints.
        if sample['threads'] != 1 or not 0 < sample['rss_bytes'] < RSS_LIMIT or sample['descriptors'] < 0:
            raise ValueError('Invalid joined download resource observation: '+str(sample))
    retained = samples[WARMUP:]
    rss = [row['rss_bytes'] for row in retained]
    descriptors = [row['descriptors'] for row in retained]
    result = dict(warmup=WARMUP, samples=len(samples), rss_range_bytes=max(rss)-min(rss),
                  descriptor_range=max(descriptors)-min(descriptors), idle_threads=1,
                  rss_limit_bytes=RSS_LIMIT, rss_growth_limit_bytes=RSS_GROWTH,
                  descriptor_growth_limit=DESCRIPTOR_GROWTH)
    if result['rss_range_bytes'] > RSS_GROWTH or result['descriptor_range'] > DESCRIPTOR_GROWTH:
        # Finite observed growth exceeding a declared budget is a failure, not a leak diagnosis.
        raise ValueError('Download resource growth exceeds soak budget: '+str(result))
    return result


def observe(binary, directory, environment):
    """Keep one native process alive through all observations; reap it on every failed boundary."""
    log = directory/'application-download-load-run.log'
    samples, peaks = [], {'driver': {}}
    started = time.monotonic()
    process = None
    result = dict(command=[str(binary)], passed=False)
    try:
        # A unique invocation gate prevents stale files from releasing a new native lifecycle.
        with tempfile.TemporaryDirectory(prefix='resource-gate-', dir=directory) as temporary:
            gate = Path(temporary)
            with log.open('w') as output:
                process = subprocess.Popen([str(binary)], cwd=directory,
                    env=dict(environment, RAGNAROK_DOWNLOAD_LOAD_GATE=str(gate)),
                    stdout=output, stderr=subprocess.STDOUT)
                for iteration in range(ROUNDS + 1):
                    # Native round cleanup precedes the marker; the gate prevents sampling the next round.
                    remaining = 180 - (time.monotonic() - started)
                    if remaining <= 0:
                        raise TimeoutError('Download resource workload deadline')
                    wait_marker({'driver': process}, {'driver': log}, 'driver',
                        f'DOWNLOAD_IDLE {iteration}', peaks, seconds=min(20, remaining),
                        thread_limits={'driver': 2})
                    sample = resources(process.pid)
                    samples.append(sample)
                    for metric, value in sample.items():
                        # Retain sampled high water observations, including the parked idle boundaries.
                        peaks['driver'][metric] = max(peaks['driver'].get(metric, 0), value)
                    if sample['threads'] != 1 or not 0 < sample['rss_bytes'] < RSS_LIMIT:
                        raise ValueError('Download idle resource bound: '+str(sample))
                    (gate/str(iteration)).touch()
                result['exit_code'] = process.wait(timeout=5)
            text = log.read_text()
            expected = [f'DOWNLOAD_IDLE {index}' for index in range(ROUNDS + 1)]
            expected.append('DOWNLOAD_LOAD cancelled=32 resets=32 adopted=1')
            if result['exit_code'] != 0 or text != '\n'.join(expected)+'\n':
                raise ValueError('Incomplete or unexpected download workload transcript')
            result.update(growth=growth(samples), passed=True)
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        # A timeout, observation failure or invalid transcript remains this workload's failed verdict.
        result['failure'] = str(error)
    finally:
        # Cleanup precedes evidence writes, so a full disk cannot strand a gated child or its worker.
        if process is not None:
            if process.poll() is None:
                process.kill()
            result['exit_code'] = process.wait()
        result.update(elapsed_seconds=round(time.monotonic()-started, 6),
                      log=str(log),
                      output=log.read_text() if log.exists() else '', idle=samples, peaks=peaks['driver'])
        (directory/'resources.json').write_text(json.dumps(result, indent=2)+'\n')
    return result
