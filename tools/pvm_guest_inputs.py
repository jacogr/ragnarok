# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Prepare bounded, provenance-checked interpreted guests for census and revision comparisons."""
import hashlib
import json
import os

from native_checks import ROOT
from native_dependencies import require_submodule
from native_fixture_contracts import load_fixture_contracts
from pvm_benchmark import CRATE, TARGET
from pvm_sieve_benchmark import verify_fixture


CASES = (('sieve', 1000), ('sieve', 100000), ('minimal', 1000), ('minimal', 100000),
         ('memset', 1000), ('memset', 100000), ('pinky', 1))


def digest(path):
    """Identify actual bytes independently of a mutable name or timestamp."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_cases(cases):
    """Admit only the complete bounded matrix or its explicit six-input control subset."""
    if (type(cases) is not tuple or cases not in (CASES, CASES[:-1])
            or any(type(guest) is not str or type(limit) is not int for guest, limit in cases)):
        raise ValueError('unsupported paired guest matrix')


def preparation_identity(output, guest, limit):
    """Require one exact reference preparation record, including canonical bounded dimensions."""
    if (type(guest) is not str or type(limit) is not int or (guest, limit) not in CASES):
        raise ValueError('unsupported guest preparation case')
    prefix = ['SIEVE_PREPARED', str(limit)] if guest == 'sieve' else [
        'GUEST_PREPARED', guest, str(limit)]
    if type(output) is not str or not output.endswith('\n') or output.count('\n') != 1:
        raise ValueError('incomplete guest preparation identity')
    fields = output[:-1].split(',')
    values = fields[len(prefix):]
    if (fields[:len(prefix)] != prefix or len(values) != 2
            or any(not value.isascii() or not value.isdecimal() or value.startswith('0')
                   for value in values)):
        raise ValueError('foreign or malformed guest preparation identity')
    pages, code = map(int, values)
    if not 0 < pages <= 1 << 20 or not 0 < code < 1 << 32:
        raise ValueError('unbounded guest preparation identity')
    return dict(mapped_pages=pages, code_bytes=code)


def prepare_inputs(checks, folder, cases=CASES):
    """Verify frozen sources, build the pinned reference offline, and prepare complete checked states."""
    validate_cases(cases)
    contracts = load_fixture_contracts(ROOT/'tests/fixtures')
    identities = {}
    for key in ('pvm_guests', 'pvm_pinky', 'pvm_sieve'):
        # Selected sizes never excuse missing licenses, source manifests or other declared members.
        for path, expected in contracts[key][2]:
            if digest(path) != expected:
                raise ValueError('changed real-guest fixture: '+path.name)
            identities[path] = expected
    pins = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
    upstream = require_submodule(pins)
    provenance = {guest: verify_fixture(upstream=upstream, guest=guest)
                  for guest in sorted({guest for guest, _ in cases})}
    sources = [*sorted(CRATE.glob('src/*.rs')), CRATE/'Cargo.toml', CRATE/'Cargo.lock',
               ROOT/'spec/polkavm-pins.json', ROOT/'spec/toolchain.json',
               ROOT/'spec/bandersnatch-pins.json', ROOT/'Makefile']
    identities.update({path: digest(path) for path in sources})
    rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    built = checks.command(['rustup', 'run', rust, 'cargo', 'build', '--release', '--locked',
        '--offline', '--manifest-path', CRATE/'Cargo.toml', '--target-dir', TARGET],
        'reference-build', timeout=900)
    built.pop('output')
    if built['exit_code']:
        raise RuntimeError('checked guest reference build failed: '+built['log'])
    reference = TARGET/'release/ragnarok-pvm-benchmark'
    identities[reference] = digest(reference)
    inputs, preparations = [], []
    for guest, limit in cases:
        # One pinned interpreted preparation supplies both endpoints with the same initial and expected state.
        destination = folder/guest/str(limit)
        destination.mkdir(parents=True, exist_ok=True)
        family = {'sieve': 'pvm_sieve', 'pinky': 'pvm_pinky'}.get(guest, 'pvm_guests')
        artifact = contracts[family][1]/(guest+'.polkavm')
        prepared = checks.command([reference, '--sieve-prepare', artifact, destination, limit, 1],
            f'prepare-{guest}-{limit}', environment=dict(os.environ, RAGNAROK_PVM_GUEST=guest),
            timeout=180)
        output = prepared.pop('output')
        if prepared['exit_code']:
            raise RuntimeError('checked guest preparation failed: '+prepared['log'])
        identity = preparation_identity(output, guest, limit)
        data, expected = destination/f'input-{limit}.bin', destination/f'expected-{limit}.bin'
        if not data.is_file() or not expected.is_file() or not data.stat().st_size or not expected.stat().st_size:
            raise ValueError('missing complete prepared guest state')
        identities.update({path: digest(path) for path in (data, expected)})
        inputs.append((guest, limit, data, expected))
        preparations.append(dict(guest=guest, limit=limit, identity=identity, preparation=prepared))
    return dict(inputs=inputs, preparations=preparations, identities=identities,
                provenance=provenance, builds=[built], reference=reference)
