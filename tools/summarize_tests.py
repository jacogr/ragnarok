#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Render measured test/audit results in GitHub summaries without turning missing or partial evidence green.

Exposes summarize and a CLI that renders retained verification evidence into Markdown summaries.
"""
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
    elif kind == 'pvm-reference':
        # The optional paired-reference job owns a stricter completeness check and its own table.
        from pvm_reference_summary import summarize_reference
        return summarize_reference(report)
    elif kind == 'runtime':
        corpora = {key: value for key, value in report.items() if key.endswith('_corpus')}
        scope = ''
        if report.get('unit_shard') is not None:
            # A successful partition is not a claim that every other partition ran or passed.
            index, count = report['unit_shard']
            scope = f' — shard {index}/{count}'
        lines = ['## Native unit and codec verification'+scope, '', '**Status: '+report['status']+'**', '',
                 f'- Native suites: {len(report["suites"])}', f'- Independent corpora: {len(corpora)}',
                 '',
                 'Passing implemented-scope tests is partial evidence, not full JAM client conformance.',
                 'Independent corpus verdicts are listed below.', '',
                 '| Corpus | Result | Requests |', '| --- | --- | --- |']
        # Preserve each corpus verdict rather than presenting aggregate counts as a substitute for failures.
        for key, row in corpora.items():
            lines.append('| `'+key+'` | '+('Pass' if row['passed'] else 'Fail')+' | '+str(row.get('requests', 'vectors/threads'))+' |')
    elif kind == 'failures':
        # Runtime contracts own a separate inventory; compiler rejections belong to the guards job.
        from failure_plans import failure_partition
        plans, specialized = failure_partition(report.get('failure_shard'))
        scope = ''
        if report.get('failure_shard') is not None:
            # Subset evidence identifies its actual partition rather than claiming every contract family.
            index, count = report['failure_shard']
            scope = f' — shard {index}/{count}'
        lines = ['## Runtime failure and contract verification'+scope, '', '**Status: '+report['status']+'**', '',
                 '| Group | Passed | Total |', '| --- | --- | --- |']
        for key in plans:
            # Include failed rows and positive runtime controls rather than claiming every row is a rejection.
            rows = report[key]
            lines.append('| '+key+' | '+str(sum(row['passed'] for row in rows))+' | '+str(len(rows))+' |')
        if specialized:
            # Positive controls belong only to the partition that actually executed them.
            lines += ['', 'Store positive controls: '+('Pass' if report['store_controls']['passed'] else 'Fail')+'.']
    elif kind == 'guards':
        # Compiler rejections have their own verdict and inventory, never inferred from a unit result.
        lines = ['## Compiler rejection guards', '', '**Status: '+report['status']+'**', '',
                 '| Group | Passed | Total |', '| --- | --- | --- |']
        for key in ('privacy', 'nominal', 'contracts', 'schemas', 'ownership_compile'):
            # Failed checks remain visible within their original diagnostic family.
            rows = report[key]
            lines.append('| '+key+' | '+str(sum(row['passed'] for row in rows))+' | '+str(len(rows))+' |')
    elif kind == 'python':
        # This group owns discovery only; it never claims native or networking coverage.
        lines = ['## Python reference/tooling verification', '', '**Status: '+report['status']+'**', '',
                 'Tests: '+str(report['tests'])+'; skipped: '+str(report['skipped'])+'.']
    elif kind == 'e2e':
        # Live networking keeps its own totals and resource evidence, separate from unit/corpus counts.
        lines = ['## End-to-end networking verification', '', '**Status: '+report['status']+'**', '',
                 'Entry-point selftests: '+str(len(report['suites']))+'.']
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
    parser.add_argument('--kind', choices=('runtime', 'modules', 'python', 'guards', 'failures', 'e2e', 'pvm-reference'), required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--artifact', type=Path, help='Also replace one downloadable Markdown report')
    args = parser.parse_args()
    try:
        # Do not infer a pass when setup, compilation or the runner failed before writing evidence.
        text = summarize(json.loads(args.report.read_text()), args.kind)
    except (OSError, ValueError, KeyError, TypeError) as error:
        # Setup/report failures stay visible even if no normal JSON evidence exists.
        text = '## Verification '+args.kind+'\n\nNo usable verification report: '+str(error)+'\n'
        with args.output.open('a') as output:
            output.write(text)
        if args.artifact is not None:
            # Setup failure must replace an earlier successful downloadable summary too.
            args.artifact.write_text(text)
        raise SystemExit(1)
    with args.output.open('a') as output:
        output.write(text)
    if args.artifact is not None:
        # Artifacts contain this run's table, while Actions may append several job sections.
        args.artifact.write_text(text)


# Importing the renderer never reads reports or modifies a GitHub summary.
if __name__ == '__main__':
    main()
