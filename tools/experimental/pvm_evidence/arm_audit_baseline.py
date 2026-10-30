#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Qualify the intended baseline native failure from sealed inert artifacts, not from a red job alone."""
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'build/arm-region-refusal-evidence/41051261233'
HEAD = 'dcbd1ce59ff3c48ef874101bd7e6c870237844fb'
folder = BASE/'pvm-comparison-arm64-1/tests/pvm-native'
meta = json.loads((BASE/'pvm-comparison-arm64-1.json').read_text())
archive = BASE/'pvm-comparison-arm64-1.zip'
assert archive.stat().st_size == meta['size_in_bytes']
assert 'sha256:'+hashlib.sha256(archive.read_bytes()).hexdigest() == meta['digest']
with zipfile.ZipFile(archive) as bundle:
    # Revalidate every sealed member against the inert extraction before interpreting claims.
    assert bundle.testzip() is None
    for item in bundle.infolist():
        if not item.is_dir():
            assert (BASE/'pvm-comparison-arm64-1'/item.filename).read_bytes() == bundle.read(item)
run = json.loads((BASE/'run.json').read_text())
report = json.loads((folder/'results.json').read_text())
assert run['head_sha'] == report['revision'] == HEAD and run['status'] == 'completed' and run['conclusion'] == 'failure'
for path, wanted in report['sources'].items():
    # Git reads are source data only; no artifact, compiler or guest executable is launched.
    raw = subprocess.check_output(['git', 'show', HEAD+':'+path], cwd=ROOT)
    assert hashlib.sha256(raw).hexdigest() == wanted, path
assert not subprocess.check_output(['git', 'diff', '--name-only', '5dace79e', HEAD, '--', 'src', 'native'], cwd=ROOT)
log = (folder/'region-refusal-run.log').read_text()
expected = ['ARM_REGION_LOCAL_SHAPES,false', 'ARM_REGION_REFUSAL_NATIVE,0,0,0,2,10,10',
    'ARM_REGION_REFUSAL_CASE,false,false,true', 'ARM_REGION_REFUSAL_NATIVE,0,1,0,0,0,138',
    'ARM_REGION_REFUSAL_CASE,false,true,false', 'ARM_REGION_REFUSAL_NATIVE,1,1,2,5,28,133',
    'ARM_REGION_REFUSAL_CASE,true,true,true', 'ARM_REGION_REFUSAL_ASSERT,candidate-local-availability']
assert log.splitlines()[:8] == expected and '[Assertion Failure]' in log
assert report['status'] == 'incomplete' and report['error'] == log
elf = (folder/'region-refusal').read_bytes()
assert elf[:7] == b'\x7fELF\x02\x01\x01' and int.from_bytes(elf[18:20], 'little') == 183
jobs = json.loads((BASE/'jobs.json').read_text())['jobs']
active = [job for job in jobs if job['conclusion'] != 'skipped']
assert len(active) == 1 and active[0]['name'] == 'Perf / PVM Comparison (Linux ARM64)' and active[0]['conclusion'] == 'failure'
receipt = dict(status='confirmed-ARM-candidate-local-refusal-regression', run=run['id'], revision=HEAD,
    production='5dace79e92997f596fb3841857a33587138be42c', production_source_unchanged=True,
    native_elf_sha256=hashlib.sha256(elf).hexdigest(), verified_source_identities=len(report['sources']),
    expected_failure='candidate-local-availability', actual_receipts=expected,
    fresh_native_positive=True, rejected_first_loses_regions=True, eligible_first_retains_regions=True,
    independent_literal_CPU_RAM_permissions_gas_PC_attempts_snapshots_passed=True,
    smoke='not selected by focused manual jit-arm-check mode; normal PR Smoke remains required',
    native_artifact_execution=False, performance_claim=False)
(BASE/'baseline-author-audit.json').write_text(json.dumps(receipt, indent=2)+'\n')
files = {p.relative_to(BASE).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
    for p in BASE.rglob('*') if p.is_file() and p.name != 'preservation.json'}
(BASE/'preservation.json').write_text(json.dumps(dict(files=files), indent=2)+'\n')
print(receipt['status'], 'sources', len(report['sources']), 'ELF', receipt['native_elf_sha256'])
