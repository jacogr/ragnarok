#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run opt-in differential renderer checks; no production or CI entry point is changed."""
import argparse
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import subprocess
import statistics
import sys
import time


# Load only the unchanged renderer, without triggering production orchestration.
def load_oracle(root):
    spec = importlib.util.spec_from_file_location('oracle', root/'tools/pvm_reference_summary.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.summarize_reference


# Freeze representative producer reports and adversarial variants of the existing source tests.
def corpus():
    base = dict(status='checks-passed', planned=[dict(binary='memory', suite='pvm_memory_access_reference')],
                completed=['memory'], checks=[dict(name=name, exit_code=0)
                    for name in ('build', 'memory-reference', 'memory-native')])
    cases = [('complete', base)]
    # Successful metadata includes Unicode whitespace, codepoint truncation and hostile table text.
    enriched = deepcopy(base)
    enriched.update(head='a&<b>|`c`\n\t d', platform='é😀'*400,
                    backend='compiler', rust='a\u001cb\u0085c\u2007d\u202fe',
                    graypaper=None, polkavm=123)
    enriched['planned'][0]['engine'] = False
    cases.append(('escaped-neutral', enriched))
    # Failed/running reports may legitimately contain absent or nonzero stages.
    for status in ('failed', 'running'):
        data = deepcopy(base)
        data.update(status=status, completed=[], error='broken <setup> | `x` & more')
        data['checks'] = [dict(name='build', exit_code=7)]
        cases.append((status, data))
    cases += [('empty-failed', dict(status='failed')), ('empty-running', dict(status='running'))]
    # Each mutation isolates a distinct evidence-validation branch of the unchanged renderer.
    mutations = [
        ('missing-stage', lambda d: d['checks'].pop()),
        ('failed-stage', lambda d: d['checks'][-1].update(exit_code=7)),
        ('duplicate-stage', lambda d: d['checks'].append(dict(d['checks'][0]))),
        ('incomplete', lambda d: d['completed'].clear()),
        ('duplicate-plan', lambda d: d['planned'].append(dict(d['planned'][0]))),
        ('unknown-stage', lambda d: d['checks'][-1].update(name='unknown')),
        ('bool-exit', lambda d: d['checks'][-1].update(exit_code=False)),
        ('float-exit', lambda d: d['checks'][-1].update(exit_code=0.0)),
        ('string-exit', lambda d: d['checks'][-1].update(exit_code='0')),
        ('duplicate-completed', lambda d: d['completed'].append('memory')),
        ('unknown-completed', lambda d: d['completed'].append('other')),
        ('invalid-binary', lambda d: d['planned'][0].update(binary='x|injection')),
        ('invalid-suite', lambda d: d['planned'][0].update(suite='pvm_A')),
        ('empty-suite', lambda d: d['planned'][0].update(suite='pvm_')),
        ('unknown-status', lambda d: d.update(status='green')),
        ('missing-status', lambda d: d.pop('status')),
        ('null-plan', lambda d: d.update(planned=None)),
        ('null-checks', lambda d: d.update(checks=None)),
        ('null-completed', lambda d: d.update(completed=None)),
        ('empty-success', lambda d: d.update(planned=[], checks=[], completed=[])),
    ]
    for name, mutate in mutations:
        data = deepcopy(base)
        mutate(data)
        cases.append((name, data))
    # Ordering and ASCII identity restrictions must hold for more than one pair too.
    multiple = deepcopy(base)
    multiple['planned'].append(dict(binary='gas-2_test', suite='pvm_gas'))
    multiple['completed'].append('gas-2_test')
    multiple['checks'] += [dict(name='gas-2_test'+suffix, exit_code=0)
                           for suffix in ('-reference', '-native')]
    cases.append(('multiple', multiple))
    reversed_pairs = deepcopy(multiple)
    reversed_pairs['completed'].reverse()
    cases.append(('reversed-completed', reversed_pairs))
    for value in (False, 0, '', None, [], {}):
        data = deepcopy(base)
        data['planned'][0]['engine'] = value
        cases.append(('false-engine-'+repr(value), data))
    return cases


# Preserve exact successful bytes; normalize Python/compiler diagnostic formats to rejection only.
def observe(oracle, report):
    try:
        return oracle(deepcopy(report))
    except (ValueError, KeyError, TypeError):
        return None


# Self-check the oracle comparator, then exercise VM and reusable compiled Nim implementations.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--script', type=Path)
    parser.add_argument('--nim', help='Override the bundled pinned Nim 2 executable')
    args = parser.parse_args()
    script = args.script or args.root/'tools/pvm_reference_summary.nims'
    if args.nim is None:
        # Reuse the existing verified formatter archive; do not expose Nim 2 on production PATH.
        sys.path.insert(0, str(args.root/'tools'))
        from setup_nimony import installed
        _, formatter = installed()
        args.nim = str(formatter.resolve().with_name('nim'))
    oracle = load_oracle(args.root)
    cases = corpus()
    expected = [observe(oracle, data) for _, data in cases]
    assert expected == [observe(oracle, data) for _, data in cases], 'Oracle self-check failed'
    # Keep all generated inputs, binaries, compiler caches and full logs under ignored build/.
    folder = args.root/'build/nimscript-poc'
    folder.mkdir(parents=True, exist_ok=True)
    # A failed rerun must never leave an earlier success report available as fresh evidence.
    (folder/'results.json').unlink(missing_ok=True)
    results = {}
    modes = {'nimscript': [args.nim, 'e', '--hints:off', str(script), '--']}
    for mode, flags in (('debug', []), ('release', ['-d:release'])):
        binary = folder/mode
        compiled_source = folder/'pvm_reference_summary.nim'
        compiled_source.write_bytes(script.read_bytes())
        command = [args.nim, 'c', '--hints:off', *flags, '--nimcache:'+str(folder/(mode+'-cache')),
                   '-o:'+str(binary), str(compiled_source)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=120)
        (folder/(mode+'-build.log')).write_text(built.stdout+built.stderr)
        assert built.returncode == 0, built.stderr
        modes[mode] = [str(binary)]
    for mode, command in modes.items():
        started = time.perf_counter()
        logs = []
        for (name, data), wanted in zip(cases, expected):
            source, output = folder/'input.json', folder/'output.md'
            source.write_text(json.dumps(data))
            output.unlink(missing_ok=True)
            ran = subprocess.run([*command, str(source), str(output)], capture_output=True, text=True, timeout=30)
            logs.append(name+'\n'+ran.stdout+ran.stderr)
            (folder/(mode+'.log')).write_text('\n'.join(logs))
            assert (ran.returncode == 0) == (wanted is not None), (mode, name, ran.stderr)
            if wanted is not None:
                assert output.read_bytes() == wanted.encode(), (mode, name, 'Markdown mismatch')
            else:
                assert not output.exists(), (mode, name, 'Rejected report wrote output')
        results[mode] = dict(cases=len(cases), elapsed_seconds=round(time.perf_counter()-started, 3))
    # Compare equal complete-report file renders, including fresh process startup in each sample.
    source, output = folder/'input.json', folder/'output.md'
    source.write_text(json.dumps(cases[0][1]))
    python_command = [sys.executable, '-c',
        'import sys,json; from pathlib import Path; '
        'sys.path.insert(0,sys.argv[1]); '
        'from pvm_reference_summary import summarize_reference; '
        'Path(sys.argv[3]).write_text(summarize_reference(json.loads(Path(sys.argv[2]).read_text())))',
        str(args.root/'tools')]
    timings = {}
    for mode, command in {'python': python_command, **modes}.items():
        samples = []
        for _ in range(5):
            started = time.perf_counter()
            ran = subprocess.run([*command, str(source), str(output)], capture_output=True, timeout=30)
            assert ran.returncode == 0, ran.stderr
            assert output.read_bytes() == expected[0].encode()
            samples.append(time.perf_counter()-started)
        timings[mode] = round(statistics.median(samples), 4)
    results['startup_render_median_seconds'] = timings
    (folder/'results.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps(results))


# Direct invocation is intentional: this experiment does not add a compiler requirement to check-python.
if __name__ == '__main__':
    main()
