#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Sample fresh macOS journal consumers from an admitted, unchanged matched churn panel."""
import argparse
import json
import platform
import subprocess
from pathlib import Path
import storage_light_journal_benchmark as paired
from native_checks import ROOT


def validate(panel, folder):
    """Require completed raw workload admission and exact current sources, compiler, binary and native observers."""
    paired.summarize(panel)
    if panel['sources'] != paired.identities():
        raise ValueError('Profile panel sources changed')
    files = {folder/'matched-light-churn': panel['binary_sha256'],
             Path(panel['compiler']): panel['compiler_sha256'],
             folder/'libcrypto_observed.dylib': panel['native_libraries']['observer'],
             folder/'storage-io-observer.o': panel['native_libraries']['storage_io']}
    for path, expected in files.items():
        # Old binaries and newly rebuilt observers cannot silently become the measured source tree.
        if paired.baseline.digest(path) != expected:
            raise ValueError('Profile executable input changed: '+str(path))
    for size in paired.baseline.SIZES:
        expected = panel['fixtures'][str(size)]
        if paired.baseline.digest(folder/('source-'+str(size))/'CURRENT') != expected['sha256']:
            raise ValueError('Profile fixture changed')


def admit(raw, size, exit_code, checkpoint_digest, expected_digest, sample):
    """Sampling never substitutes for native success, exact deterministic work or canonical selected image bytes."""
    if type(exit_code) is not int or exit_code != 0 or checkpoint_digest != expected_digest:
        raise ValueError('Profile consumer failed or changed checkpoint')
    if not sample.strip() or 'Call graph:' not in sample:
        raise ValueError('Missing native sample call graph')
    return paired.parse(raw, size, 'journal')


def run(panel_folder, output):
    """Sample six serial fresh processes; preserve all artifacts and refuse unsupported hosts before mutation."""
    if platform.system() != 'Darwin':
        raise ValueError('This sampler requires macOS /usr/bin/sample')
    folder, output = Path(panel_folder).resolve(), Path(output).resolve()
    if not folder.is_relative_to(ROOT/'build') or not output.is_relative_to(ROOT/'build'):
        raise ValueError('Use panel and output directories under build/')
    panel = json.loads((folder/'results.json').read_text())
    validate(panel, folder)
    output.mkdir(parents=True, exist_ok=False)
    report = dict(status='running', panel_sha256=paired.baseline.digest(folder/'results.json'),
                  tool_sha256=paired.baseline.digest(__file__), binary_sha256=panel['binary_sha256'],
                  platform=platform.platform(), runs=[])
    def save():
        """Partial evidence remains explicitly incomplete after any sampler or child failure."""
        (output/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    save()
    try:
        for round_number in range(3):
            for size in paired.baseline.SIZES if round_number%2 == 0 else reversed(paired.baseline.SIZES):
                # Each actual journal update/reopen owns a new namespace and retains its pre-edit reader.
                name = str(size)+'-'+str(round_number)
                target, sample_path = output/('target-'+name), output/('sample-'+name+'.txt')
                expected = panel['fixtures'][str(size)]
                args = [str(folder/'matched-light-churn'), 'journal', str(size),
                        str(folder/('source-'+str(size))), expected['root'], str(target)]
                with (output/('child-'+name+'.log')).open('w+') as log:
                    child = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT)
                    try:
                        sampled = subprocess.run(['/usr/bin/sample', str(child.pid), '1', '1', '-mayDie',
                                                  '-file', str(sample_path)], capture_output=True, text=True, timeout=10)
                        code = child.wait(timeout=30)
                    finally:
                        # A failed profiler cannot leave an unobserved native writer running in the namespace.
                        if child.poll() is None:
                            child.kill(); child.wait()
                    log.seek(0); raw = log.read()
                (output/('sampler-'+name+'.log')).write_text(sampled.stdout+sampled.stderr)
                if sampled.returncode != 0:
                    raise ValueError('Native sampler failed')
                observed = admit(raw, size, code, paired.baseline.digest(target/'snapshot-0000000000000001.bin'),
                                 expected['sha256'], sample_path.read_text())
                report['runs'].append(dict(size=size, round=round_number, command=args, exit_code=code,
                                           raw=raw, observed=observed, sample_sha256=paired.baseline.digest(sample_path)))
                save()
        validate(panel, folder)
        if report['panel_sha256'] != paired.baseline.digest(folder/'results.json') or report['tool_sha256'] != paired.baseline.digest(__file__):
            raise ValueError('Profile authority changed during sampling')
        report['status'] = 'checks-passed'; save()
    except Exception as error:
        # Raw failure evidence is retained; no timing/RSS summary is inferred from instrumented children.
        report.update(status='failed', error=str(error)); save()
        raise
    print('PASS reconstruction profiles: '+str(output/'results.json'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--panel', required=True)
    parser.add_argument('--output', required=True)
    options = parser.parse_args()
    run(options.panel, options.output)
