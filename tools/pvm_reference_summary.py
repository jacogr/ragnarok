# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Render complete or partial differential evidence without turning missing stages into passes."""
import re


# Bound external report text and prevent Markdown table/HTML injection in Actions summaries.
def cell(value):
    text = ' '.join(str(value).split())[:500]
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('|', r'\|').replace('`', "'")


# The report's process statuses are evidence; its top-level success string alone is insufficient.
def summarize_reference(report):
    status = report['status']
    if status not in ('running', 'failed', 'checks-passed'):
        raise ValueError('Unknown PVM reference status')
    plan = report.get('planned', [])
    names = [item['binary'] for item in plan]
    if len(set(names)) != len(names):
        raise ValueError('Duplicate PVM comparison identity')
    for item in plan:
        # Source-owned identities need no Markdown escaping or inference from observed process output.
        if (not re.fullmatch(r'[a-z][a-z0-9_-]*', item['binary'])
                or not re.fullmatch(r'pvm_[a-z_]+', item['suite'])):
            raise ValueError('Invalid PVM comparison identity')
    expected = {'build', *(name+suffix for name in names for suffix in ('-reference', '-native'))}
    stages = {}
    for item in report.get('checks', []):
        # Reject duplicate/unknown records and malformed exit codes instead of selecting the last result.
        name = item['name']
        if name not in expected or name in stages or type(item['exit_code']) is not int:
            raise ValueError('Invalid or duplicate PVM process evidence')
        stages[name] = item['exit_code']
    completed = report.get('completed', [])
    if len(set(completed)) != len(completed) or not set(completed) <= set(names):
        raise ValueError('Invalid completed PVM comparisons')
    if status == 'checks-passed':
        # A forged green status cannot hide a missing native/reference process or incomplete pair.
        if (not plan or set(stages) != expected or any(stages.values())
                or completed != names):
            raise ValueError('Incomplete or failed PVM evidence marked successful')
    lines = ['## PVM reference comparisons', '', '**Status: '+cell(status)+'**', '',
             'Correctness checks only. Execution durations are diagnostics; no speed comparison is claimed.', '',
             f'Completed pairs: {len(completed)}/{len(plan)}.', '',
             '| Comparison | PolkaVM | Ragnarök native suite |', '| --- | --- | --- |']

    # Render missing stages explicitly so a setup failure or interrupted run cannot look like a pass.
    def verdict(name):
        if name not in stages:
            return 'Not run'
        return 'Pass' if stages[name] == 0 else 'Fail (exit '+str(stages[name])+')'

    for item in plan:
        name = item['binary']
        role = ' (backend neutral)' if not item.get('engine', True) else ''
        lines.append('| `'+name+'` | '+verdict(name+'-reference')+role+' | `'+item['suite']+'`: '+verdict(name+'-native')+' |')
    lines += ['', 'Reference build: '+verdict('build')+'.']
    if report.get('error'):
        # Failed setup may not have produced a plan; keep its bounded reason visible below the empty table.
        lines += ['', 'Failure: '+cell(report['error'])]
    for key in ('head', 'graypaper', 'polkavm', 'rust', 'platform', 'backend'):
        # Record exact environment identifiers from the run, never the summary renderer's host.
        if key in report:
            lines.append('- '+key+': '+cell(report[key]))
    lines += ['', 'Download `summary.md`, `results.json` and the retained logs from this job’s '
              '`pvm-reference` artifact for detailed evidence.']
    return '\n'.join(lines)+'\n'
