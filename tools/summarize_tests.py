#!/usr/bin/env python3
"""Render measured test/audit results in GitHub summaries without turning missing or partial evidence green."""
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
        lines = ['## Source module compilation', '',
                 f'**{sum(row["passed"] for row in rows)}/{len(rows)} modules pass semantic checking.**', '',
                 'This check covers every `src/**/*.nim` file and fails for any failed or timed-out module.',
                 'It does not establish linking, runtime parity or full M1/M2/M3 coverage.', '',
                 '| Module | Semantic check |', '| --- | --- |']
        # List every module so a new failure or a newly ported module is visible in the PR.
        for row in rows:
            lines.append('| `'+row['source']+'` | '+('Pass' if row['passed'] else 'Fail')+' |')
    elif kind == 'runtime':
        # Count the actual independent evidence groups without hardcoding totals that grow during the port.
        groups = {key: value for key, value in report.items() if isinstance(value, list) and value
                  and all(isinstance(row, dict) and 'passed' in row for row in value)}
        guards = sum(len(rows) for key, rows in groups.items() if key not in ('suites', 'runtime', 'privacy', 'nominal', 'schemas', 'contracts', 'ownership_compile'))
        compilations = sum(len(report[key]) for key in ('privacy', 'nominal', 'schemas'))+len(report.get('contracts', []))+len(report.get('ownership_compile', []))
        corpora = {key: value for key, value in report.items() if key.endswith('_corpus')}
        lines = ['## Runtime verification', '', '**Status: '+report['status']+'**', '',
                 f'- Native suites: {len(report["suites"])}', f'- Independent corpora: {len(corpora)}',
                 f'- Runtime misuse rejections: {guards}', f'- Compilation rejections: {compilations}', '',
                 'Passing implemented-scope tests is partial evidence, not full JAM client conformance.',
                 'Corpus and lifecycle verdicts are listed below.', '',
                 '| Corpus | Result | Requests |', '| --- | --- | --- |']
        # Preserve each corpus verdict rather than presenting aggregate counts as a substitute for failures.
        for key, row in corpora.items():
            lines.append('| `'+key+'` | '+('Pass' if row['passed'] else 'Fail')+' | '+str(row.get('requests', 'vectors/threads'))+' |')
        if 'quic_peer' in report:
            # Keep authenticated exchanges distinct from pure corpora and failed-result contract probes.
            peer = report['quic_peer']
            lines += ['', 'Authenticated CE 143 peer matrix: '+('Pass' if peer['passed'] else 'Fail')+'.',
                      'Matrix cases: '+str(peer.get('matrix_cases', 'N/A'))+'; repeated valid startups: '+str(peer.get('repeated_valid', 'N/A'))+'.']
        for key, label in (('quic_service', 'Retained CE 143 service'),
                           ('quic_integration_service', 'Integrated digest service')):
            if key in report:
                # Each workload keeps its own verdict; missing numeric observations are never inferred as zero.
                row = report[key]
                lines += ['', label+': '+('Pass' if row['passed'] else 'Fail')+'.']
                if row['passed']:
                    # Report measured waves/connections without confusing live networking with pure codec corpora.
                    result = row['result']
                    rounds = result.get('rounds', len(result['idle']))
                    connections = result['accepted_and_retired_connections'] if key == 'quic_service' else result['connections']
                    lines += ['Waves: '+str(rounds)+'; retired connections: '+str(connections)+'.']
        if 'quic_offload' in report:
            # Actual Rust activity, bounded worker counts and joined shutdown have their own lifecycle verdict.
            row = report['quic_offload']
            lines += ['', 'Bounded proof offload: '+('Pass' if row['passed'] else 'Fail')+'.']
            if row['passed']:
                # Network/worker observations are not independent codec corpora or compiler rejection probes.
                result = row['result']
                lines += ['Waves: '+str(result['rounds'])+'; workers: '+str(result['workers'])+
                          '; job cap: '+str(result['job_cap'])+'; verified jobs: '+str(result['verified_jobs'])+
                          '; lightweight queries: '+str(result['healthy_light_queries'])+'.']
        if 'quic_endpoint_soak' in report:
            # Endpoint destruction is separate from retained listeners and must keep its own failing verdict.
            row = report['quic_endpoint_soak']
            lines += ['', 'Same-process endpoint teardown soak: '+('Pass' if row['passed'] else 'Fail')+'.']
            if row['passed']:
                # Count sessions once per pair, not twice for its two endpoints or as codec/compiler tests.
                lines += ['Sessions: '+str(row['result']['rounds'])+'; five healthy and three adversarial streams/session.']
        for key, label in (('quic_admission', 'Connection/stream admission recovery'),
                           ('quic_closed_before_request', 'Authenticated connection loss before request')):
            if key in report:
                # Keep each resilience verdict visible without adding network waves to codec/compiler totals.
                row = report[key]
                lines += ['', label+': '+('Pass' if row['passed'] else 'Fail')+'.']
                if row['passed']:
                    # Display measured outcomes; absent fields must fail rather than fabricate successful coverage.
                    result = row['result']
                    if key == 'quic_admission':
                        lines += ['Waves: '+str(result['waves'])+'; retired connections: '+str(result['retired_connections'])+
                                  '; healthy queries after release: '+str(result['healthy_queries_after_release'])+'.']
                    else:
                        # Zero application streams is intentional: the connection itself must settle failure.
                        lines += ['Application streams: '+str(result['application_streams'])+
                                  '; close detection seconds: '+str(result['closed_seconds'])+'.']
        for key, label in (('quic_mesh', 'Retained IPv6 mesh'),
                           ('quic_mesh_disruption', 'IPv6 peer-death recovery')):
            if key in report:
                # Keep reconnect and killed-peer outcomes separate from ordinary one-shot/service coverage.
                row = report[key]
                lines += ['', label+': '+('Pass' if row['passed'] else 'Fail')+'.']
                if row['passed']:
                    # Count actual protocol/recovery outcomes without inflating codec or compiler metrics.
                    result = row['result']
                    if key == 'quic_mesh':
                        lines += ['Reconnect rounds: '+str(result['rounds'])+'; bidirectional queries: '+str(result['bidirectional_queries'])+'.']
                    else:
                        lines += ['Peer deaths: '+str(result['peer_losses'])+'; pending operations settled: '+str(result['pending_operations_settled'])+'.']
    else:
        # Unknown report schemas must fail loudly instead of generating a misleading empty summary.
        raise ValueError('Unknown summary kind: '+kind)
    return '\n'.join(lines)+'\n'


# Missing reports produce an explicit summary and a failing helper, preserving the preceding job failure.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=('runtime', 'modules'), required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        # Do not infer a pass when setup, compilation or the runner failed before writing evidence.
        text = summarize(json.loads(args.report.read_text()), args.kind)
    except (OSError, ValueError, KeyError, TypeError) as error:
        # Setup/report failures stay visible even if no normal JSON evidence exists.
        with args.output.open('a') as output:
            output.write('## Verification '+args.kind+'\n\nNo usable verification report: '+str(error)+'\n')
        raise SystemExit(1)
    with args.output.open('a') as output:
        output.write(text)


# Importing the renderer never reads reports or modifies a GitHub summary.
if __name__ == '__main__':
    main()
