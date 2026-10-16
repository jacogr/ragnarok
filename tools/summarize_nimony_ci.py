#!/usr/bin/env python3
"""Render measured trial/audit results in GitHub summaries without turning missing or partial evidence green."""
import argparse
import json
from pathlib import Path


# Summarize an existing report only; the original command's exit status remains authoritative in the workflow.
def summarize(report, kind):
    if kind == 'modules':
        # Module checks are explicitly distinct from linked/runtime conformance and complete migration parity.
        rows = report['modules']
        if not rows:
            raise ValueError('Module report has no checked sources')
        lines = ['## Nimony remaining module compilation', '',
                 f'**{sum(row["passed"] for row in rows)}/{len(rows)} modules pass semantic checking.**', '',
                 'This check covers every `src/**/*.nim` file and fails for any failed or timed-out module.',
                 'It does not establish linking, runtime parity or full M1/M2/M3 coverage.', '',
                 '| Module | Semantic check |', '| --- | --- |']
        # List every module so a new failure or a newly ported module is visible in the PR.
        for row in rows:
            lines.append('| `'+row['source']+'` | '+('Pass' if row['passed'] else 'Fail')+' |')
    elif kind == 'slice':
        # Count the actual independent evidence groups without hardcoding totals that grow during the port.
        groups = {key: value for key, value in report.items() if isinstance(value, list) and value
                  and all(isinstance(row, dict) and 'passed' in row for row in value)}
        guards = sum(len(rows) for key, rows in groups.items() if key not in ('suites', 'runtime', 'privacy', 'nominal', 'schemas', 'contracts'))
        compilations = sum(len(report[key]) for key in ('privacy', 'nominal', 'schemas'))+len(report.get('contracts', []))
        corpora = {key: value for key, value in report.items() if key.endswith('_corpus')}
        lines = ['## Nimony migrated runtime slice', '', '**Status: '+report['status']+'**', '',
                 f'- Native suites: {len(report["suites"])}', f'- Independent corpora: {len(corpora)}',
                 f'- Runtime misuse rejections: {guards}', f'- Compilation rejections: {compilations}', '',
                 'A passing migrated slice is partial evidence. Validation-entry-point coverage, contextual crypto/',
                 'Bandersnatch, QUIC and full integration/runtime checks are still migration gates.', '',
                 '| Corpus | Result | Requests |', '| --- | --- | --- |']
        # Preserve each corpus verdict rather than presenting aggregate counts as a substitute for failures.
        for key, row in corpora.items():
            lines.append('| `'+key+'` | '+('Pass' if row['passed'] else 'Fail')+' | '+str(row.get('requests', 'vectors/threads'))+' |')
    else:
        # Unknown report schemas must fail loudly instead of generating a misleading empty summary.
        raise ValueError('Unknown summary kind: '+kind)
    return '\n'.join(lines)+'\n'


# Missing reports produce an explicit summary and a failing helper, preserving the preceding job failure.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=('slice', 'modules'), required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        # Do not infer a pass when setup, compilation or the runner failed before writing evidence.
        text = summarize(json.loads(args.report.read_text()), args.kind)
    except (OSError, ValueError, KeyError, TypeError) as error:
        # Setup/report failures stay visible even if no normal JSON evidence exists.
        with args.output.open('a') as output:
            output.write('## Nimony '+args.kind+'\n\nNo usable verification report: '+str(error)+'\n')
        raise SystemExit(1)
    with args.output.open('a') as output:
        output.write(text)


# Importing the renderer never reads reports or modifies a GitHub summary.
if __name__ == '__main__':
    main()
