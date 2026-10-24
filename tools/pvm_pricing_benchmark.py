#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Measure checked exact-start pricing queries, retaining cold rows and warm medians."""
import hashlib
import json
import platform
import statistics
import subprocess

from native_checks import NativeChecks, ROOT
from setup_nimony import installed


def parse_output(output):
    """Require every ordered sample and independent checksum before publishing timings."""
    rows = []
    for line in output.splitlines():
        # Native assertions are necessary but the report also validates the full row protocol.
        parts = line.split(',')
        if len(parts) != 5 or parts[0] != 'PVM_PRICING_LOOKUP':
            raise ValueError('invalid pricing sample row')
        mode, sample, elapsed, checksum = map(int, parts[1:])
        expected = divmod(len(rows), 13)
        if (mode, sample) != expected or mode > 1 or elapsed <= 0 or checksum != 3000000:
            raise ValueError('invalid pricing sample identity, timing or checksum')
        rows.append(dict(mode=mode, sample=sample, execution_ns=elapsed, checksum=checksum))
    if len(rows) != 26:
        raise ValueError('incomplete pricing samples')
    return rows


def main():
    """Use the provisioned pinned checked profile and retire stale reports before rebuilding."""
    folder = ROOT/'build/tests/pvm-pricing'
    folder.mkdir(parents=True, exist_ok=True)
    report = folder/'results.json'
    report.unlink(missing_ok=True)
    compiler, _ = installed()
    build, binary = NativeChecks(folder).build(
        compiler, ROOT/'tests/performance/pvm_pricing_lookup.nim', 'pricing')
    output = build.pop('output')
    (folder/'build.log').write_text(output)
    if build['exit_code'] or 'Error:' in output or 'FAILURE' in output:
        raise RuntimeError('pricing build failed; see build.log')
    completed = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
    (folder/'run.log').write_text(completed.stdout+completed.stderr)
    if completed.returncode:
        raise RuntimeError('pricing controls failed; see run.log')
    rows = parse_output(completed.stdout)
    medians = {}
    for mode, name in enumerate(('planned', 'memo')):
        # Keep cold samples in the report; summarize the ten final observations separately.
        medians[name] = statistics.median(
            row['execution_ns'] for row in rows if row['mode'] == mode and row['sample'] >= 3)
    sources = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
               for path in sorted((ROOT/'src/pvm').glob('*.nim'))}
    source = ROOT/'tests/performance/pvm_pricing_lookup.nim'
    sources[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
    report.write_text(json.dumps(dict(build=build, samples=rows, warm_median_ns=medians,
        source_sha256=sources, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
        platform=platform.platform(), machine=platform.machine()), indent=2)+'\n')
    print('PASS pricing lookups: 26 samples, 2000000 queries/sample; cold rows retained')
    print(json.dumps(medians, sort_keys=True))


# Imported parsers never provision compilers or execute native programs.
if __name__ == '__main__':
    main()
