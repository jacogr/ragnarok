#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Generate, replay and deterministically reduce bounded independent STF reporting histories.

Use the existing corpus runner to build a checked lateHistories scenario binary. This tool accepts
that explicit binary; it never bootstraps dependencies, substitutes expected native states, weakens
runtime budgets or treats a subprocess timeout as a protocol comparison result.
"""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tests'))
import current_stf_generated_oracle as oracle
from reporting_scenario_oracle import collect


def minimize(events, fails):
    """Return a deletion-1-minimal nonempty event list under a deterministic failure predicate."""
    current = deepcopy(events)
    if not current or not fails(deepcopy(current)):
        raise ValueError('initial nonempty history must reproduce the failure')
    # Chunk deletion accelerates reduction; a final singleton sweep establishes the stated property.
    width = max(1, len(current)//2)
    while width:
        start = 0
        while start < len(current):
            trial = current[:start]+current[start+width:]
            if trial and fails(deepcopy(trial)):
                current = trial
                start = 0  # Later deletions can make an earlier event removable for a nonmonotone predicate.
            else:
                start += width  # Advance only when this removal does not preserve the failure.
        width //= 2
    return deepcopy(current)


def compare(expected, actual, exit_code):
    """Classify complete byte-for-byte output mismatches without accepting truncated or nonzero runs."""
    lines = actual.splitlines()
    if exit_code == 0 and actual == '\n'.join(expected)+'\n':
        return None
    index = next((i for i, (a, e) in enumerate(zip(lines, expected)) if a != e), min(len(lines), len(expected)))
    actual_kind = lines[index].split()[0] if index < len(lines) and lines[index].split() else '<missing>'
    expected_kind = expected[index].split()[0] if index < len(expected) else '<end>'
    return dict(exit_code=exit_code, index=index, actual_kind=actual_kind, expected_kind=expected_kind)


def fingerprint(failure):
    """Preserve the comparator failure class during reduction, without claiming an identical root cause."""
    return tuple(failure[k] for k in ('exit_code', 'actual_kind', 'expected_kind')) if failure else None


def replay(seed, events, folder, binary=None, fixture=ROOT/'tests/fixtures/state-report.bin'):
    """Freeze complete independent requests/answers first, then optionally execute one actual checked driver."""
    case = oracle.scenario(seed, events)
    requests, expected, evidence = collect([case], oracle.FIXTURE, oracle.SOURCES, False)
    folder.mkdir(parents=True, exist_ok=False)
    request_path = folder/'requests.txt'
    request_path.write_text('\n'.join(requests)+'\n')
    expected_path = folder/'expected.txt'
    expected_path.write_text('\n'.join(expected)+'\n')
    manifest = dict(seed=seed, events=events, mode=case['mode'], evidence=evidence,
                    graypaper_commit='1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d',
                    native_defines=list(oracle.NATIVE_DEFINES),
                    sources_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in oracle.SOURCES},
                    oracle_sha256=hashlib.sha256(Path(oracle.__file__).read_bytes()).hexdigest(),
                    requests_sha256=hashlib.sha256(request_path.read_bytes()).hexdigest(),
                    expected_sha256=hashlib.sha256(expected_path.read_bytes()).hexdigest())
    manifest.update(passed=None, failure=None)
    # Preserve seed and independently authored inputs even if launch or timeout aborts execution.
    (folder/'case.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
    failure = None
    if binary is not None:
        # Decode/build/policy/infrastructure errors remain actual process failures; no golden is repaired.
        manifest['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        manifest['fixture_sha256'] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        outcome = subprocess.run([str(binary.resolve()), str(fixture.resolve()), str(request_path.resolve())],
                                 cwd=ROOT, capture_output=True, text=True, timeout=180)
        (folder/'actual.txt').write_text(outcome.stdout)
        (folder/'stderr.txt').write_text(outcome.stderr)
        failure = compare(expected, outcome.stdout, outcome.returncode)
        manifest.update(passed=failure is None, failure=failure,
                        actual_sha256=hashlib.sha256(outcome.stdout.encode()).hexdigest(), exit_code=outcome.returncode)
    else:
        manifest.update(passed=None, failure=None)  # Generation alone supplies no native execution verdict.
    (folder/'case.json').write_text(json.dumps(manifest, indent=2, sort_keys=True)+'\n')
    return failure


def main():
    """Expose explicit bounded seed/replay inputs and retain original as well as every reduction trial."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=lambda value: int(value, 0), default=1)
    parser.add_argument('--case', type=Path, help='replay seed/events from a saved case.json')
    parser.add_argument('--output', type=Path, required=True, help='new artifact directory; existing directories are refused')
    parser.add_argument('--binary', type=Path, help='existing checked lateHistories scenario driver')
    parser.add_argument('--fixture', type=Path, default=ROOT/'tests/fixtures/state-report.bin')
    parser.add_argument('--minimize', action='store_true')
    args = parser.parse_args()
    seed, events = args.seed, oracle.decisions(args.seed)
    if args.case is not None:
        saved = json.loads(args.case.read_text())
        seed, events = saved['seed'], saved['events']  # Always regenerate expected states; saved posteriors are ignored.
    if args.minimize and args.binary is None:
        parser.error('--minimize requires an actual checked --binary')
    args.output.mkdir(parents=True, exist_ok=False)
    failure = replay(seed, events, args.output/'original', args.binary, args.fixture)
    if failure and args.minimize:
        attempts = 0
        def fails(trial):
            """Require the same coarse failure class and preserve every independently regenerated trial."""
            nonlocal attempts
            attempts += 1
            result = replay(seed, trial, args.output/('trial-'+str(attempts)), args.binary, args.fixture)
            return fingerprint(result) == fingerprint(failure)
        reduced = minimize(events, fails)
        final = replay(seed, reduced, args.output/'minimized', args.binary, args.fixture)
        if fingerprint(final) != fingerprint(failure):
            raise RuntimeError('minimized failure did not reproduce')
    print(json.dumps(dict(seed=seed, events=len(events), executed=args.binary is not None,
                          passed=failure is None if args.binary else None, output=str(args.output))))
    return 1 if failure else 0


if __name__ == '__main__':
    raise SystemExit(main())
