#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check source-owned bounded models, guard mutants and reachability in serial and four workers.

Only a real invariant counterexample satisfies a negative expectation. Full logs, exact
source/tool identities and current results remain under build/tests/models; failures fail Make.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
from setup_tlanif import ROOT, installed
from verification_inventory import unique_object

BUILD = ROOT/'build/tests/models'


def rewrite(source, assignments):
    """Replace exactly one explicit scalar switch; reject missing/ambiguous or arbitrary syntax."""
    for name, value in assignments.items():
        # Cases cannot inject forms, evaluate expressions or silently target misspelled switches.
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', name) or not re.fullmatch(
                r'[0-9]+|\(true\)|\(false\)', value):
            raise ValueError('Invalid model switch')
        pattern = r'\(assign '+name+r'\.0\. (?:[0-9]+|\(true\)|\(false\))\)'
        source, count = re.subn(pattern, '(assign '+name+'.0. '+value+')', source)
        if count != 1:
            raise ValueError('Expected one model switch: '+name)
    return source


def verdict(code, output):
    """Never confuse parser/tool errors, empty output or a state cap with a killed mutant."""
    if 'state limit exceeded' in output:
        return 'incomplete'
    if code == 0 and re.search(r'ok — explored [1-9][0-9]* states', output):
        return 'pass'
    if code == 2 and 'invariant violated' in output and re.search(
            r'counterexample \([1-9][0-9]* states\)', output):
        return 'violated'
    return 'error'


def normalized(output):
    """Ignore upstream memo/progress diagnostics when comparing the two exploration modes."""
    return '\n'.join(line for line in output.splitlines() if not re.match(
        r'^(memo:|symmetry reduction:|\s*\.\.\. [0-9]+ explored)', line)).strip()


def declarations(folder):
    """Discover model-local cases lexically; reject orphans, duplicate names and invalid declarations."""
    models = sorted(folder.glob('*.nif'))
    if not models or {p.stem for p in models} != {p.stem for p in folder.glob('*.json')}:
        raise ValueError('Expected nonempty paired model/case files')
    result = []
    for model in models:
        # A file owns its own expected mutants and witnesses rather than a central registry.
        data = json.loads(model.with_suffix('.json').read_text(), object_pairs_hook=unique_object)
        if set(data) != {'cases'} or not isinstance(data['cases'], list) or not data['cases']:
            raise ValueError('Invalid model cases: '+str(model))
        names = set()
        for case in data['cases']:
            # Names also become log filenames, so no path characters are permitted.
            if (set(case) != {'name', 'assignments', 'expected'} or
                    re.fullmatch(r'[a-z][a-z0-9-]*', case['name']) is None or
                    case['name'] in names or case['expected'] not in ('pass', 'violated') or
                    not isinstance(case['assignments'], dict)):
                raise ValueError('Invalid model case: '+str(model))
            rewrite(model.read_text(), case['assignments'])
            names.add(case['name'])
        result.append((model, data['cases']))
    return result


def main():
    """Run bounded checks with timeouts; retain failing evidence and reject serial/parallel disagreement."""
    BUILD.mkdir(parents=True, exist_ok=True)
    report = BUILD/'results.json'
    report.unlink(missing_ok=True)
    binary = installed()
    records = []
    for model, cases in declarations(ROOT/'tests/models'):
        for case in cases:
            # Each case gets its own concrete source so mutant diagnostics remain independently replayable.
            stem = model.stem+'-'+case['name']
            path = BUILD/(stem+'.nif')
            path.write_text(rewrite(model.read_text(), case['assignments']))
            modes = []
            for jobs in (None, 4):
                # A cap or timeout is a failed/incomplete check, never a negative expectation match.
                command = [str(binary), '--max-states:10000']
                if jobs is not None:
                    command.append('--jobs:'+str(jobs))
                command.append(str(path))
                try:
                    completed = subprocess.run(command, capture_output=True, text=True, timeout=30)
                    code, output = completed.returncode, completed.stdout+completed.stderr
                except subprocess.TimeoutExpired:
                    code, output = 124, 'model check timed out'
                (BUILD/(stem+('-serial' if jobs is None else '-parallel')+'.log')).write_text(output)
                modes.append((code, normalized(output)))
            actual = verdict(*modes[0])
            passed = actual == case['expected'] and modes[0] == modes[1]
            records.append(dict(model=model.name, case=case['name'], expected=case['expected'], verdict=actual, passed=passed,
                                source_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
            print(stem+': '+actual+', serial/parallel '+('agree' if modes[0] == modes[1] else 'DISAGREE'))
    passed = bool(records) and all(record['passed'] for record in records)
    report.write_text(json.dumps(dict(status='passed' if passed else 'failed', cases=records,
        checker_sha256=hashlib.sha256(binary.read_bytes()).hexdigest()), indent=2)+'\n')
    raise SystemExit(0 if passed else 1)


# Importing classification helpers never provisions tools or runs a model.
if __name__ == '__main__':
    main()
