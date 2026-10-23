#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run the effects probe under AddressSanitizer; never use instrumented timings as benchmarks."""
import hashlib
import json
import os
from pathlib import Path

from prepare_shared import generate_shared
from run import BUILD, HERE, ROOT, checked, digest


def main():
    """Compile an isolated sanitized profile and require all functional and timed-result assertions."""
    output = BUILD / 'effects-asan'
    output.mkdir(parents=True, exist_ok=True)
    result = output / 'results.json'
    result.unlink(missing_ok=True)
    compiler = Path(os.environ['NIMONY']).resolve()
    pins = json.loads((ROOT / 'spec/toolchain.json').read_text())
    identity = dict(line.split(':', 1) for line in
                    (compiler.parents[1] / 'NIGHTLY.txt').read_text().splitlines() if ':' in line)
    assert identity['nimony-commit'].strip() == pins['commit']
    generated = generate_shared(ROOT, BUILD)
    source = HERE / 'effect_probe.nim'
    epoch = hashlib.sha256(generated.read_bytes() + source.read_bytes()).hexdigest()[:16]
    binary = output / 'probe'
    command = [str(compiler), 'c', '--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
               '--boundchecks:on', '--passC:-flto=thin', '--passL:-flto=thin',
               '--passC:-fsanitize=address', '--passL:-fsanitize=address',
               '--passC:-fno-omit-frame-pointer', '--passC:-I' + str(HERE),
               '--nimcache:' + str(output / ('cache-' + epoch)),
               '--out:' + str(binary), str(source)]
    checked(command, output / 'compile.log')
    checked([str(binary)], output / 'run.log')
    log = (output / 'run.log').read_text()
    assert 'CHECK,1685\n' in log
    assert sum(line.startswith('EFFECT,') for line in log.splitlines()) == 300
    assert 'ERROR: AddressSanitizer' not in log
    result.write_text(json.dumps(dict(status='passed', checks=1685, command=command,
        binary_sha256=digest(binary), sources={str(p.relative_to(ROOT)): digest(p)
        for p in [source, generated, HERE / 'shared_api.nim.inc', HERE / 'prepare_shared.py',
                  HERE / 'cpu_clock.h', HERE / 'check_effects_asan.py']},
        limitations=['Instrumented timings are discarded.',
                     'AddressSanitizer is not a leak or general ownership proof.']), indent=2) + '\n')
    print('AddressSanitizer passed; 1,685 checked cases and all workload result assertions')


if __name__ == '__main__':
    main()
