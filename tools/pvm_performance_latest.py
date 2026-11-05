#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Retrieve one explicit CI attempt's complete dual-architecture PVM performance reports.

Default selection is the newest master-push CI run, including pending or failed runs: an older
green result is never substituted. Authenticated gh owns API access and artifact downloads.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

from pvm_performance_report import (ARCHITECTURES, SCHEMA, _atomic_text,
                                    publish_report, render_summary, validate_report)


def _positive(value, label):
    """Require an explicit positive decimal run/attempt ID before constructing CLI arguments."""
    if re.fullmatch(r'[1-9][0-9]*', str(value)) is None:
        raise ValueError('Invalid '+label)
    return int(value)


def _repository(repo):
    """Admit owner/repository identities, never an arbitrary API path or command argument."""
    part = r'[A-Za-z0-9][A-Za-z0-9_.-]*'
    if not isinstance(repo, str) or re.fullmatch(part+'/'+part, repo) is None:
        raise ValueError('Invalid GitHub repository')
    return repo


def _gh(arguments):
    """Use only authenticated GitHub CLI reads; do not implement credential or HTTP handling."""
    result = subprocess.run(['gh', *arguments], check=False, capture_output=True, text=True,
                            timeout=180)
    if result.returncode:
        raise RuntimeError('gh read failed: '+result.stderr[-2000:])
    return result.stdout


def _json(text):
    """Reject nonstandard numbers and ambiguous duplicate fields before interpreting external data."""
    def invalid(value):
        """NaN/infinity cannot represent measured evidence or immutable identity."""
        raise ValueError('Non-finite JSON value: '+value)

    def unique(pairs):
        """One JSON field has one value; different consumers must not select conflicting identities."""
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON field: '+key)
            result[key] = value
        return result

    return json.loads(text, parse_constant=invalid, object_pairs_hook=unique)


def select_run(repo, run_id=None, attempt=None, gh=None):
    """Select newest master push or explicitly requested CI history, without green fallback."""
    repo = _repository(repo)
    gh = _gh if gh is None else gh
    if run_id is None:
        # No conclusion filter: failed/pending newest master remains the selected, visible result.
        result = _json(gh(['api', f'repos/{repo}/actions/workflows/ci.yml/runs?event=push&branch=master&per_page=1']))
        runs = result.get('workflow_runs')
        if not isinstance(runs, list) or len(runs) != 1:
            raise ValueError('No newest master-push CI run')
        run = runs[0]
    else:
        run_id = _positive(run_id, 'run ID')
        run = _json(gh(['api', f'repos/{repo}/actions/runs/{run_id}']))
    if not isinstance(run, dict):
        raise ValueError('Malformed workflow run')
    selected_id = _positive(run.get('id'), 'selected run ID')
    if run_id is not None and selected_id != run_id:
        raise ValueError('Foreign historical run response')
    if attempt is not None:
        # Older attempts are accessible only through an explicit request, not an automatic fallback.
        attempt = _positive(attempt, 'attempt')
        run = _json(gh(['api', f'repos/{repo}/actions/runs/{selected_id}/attempts/{attempt}']))
        if not isinstance(run, dict) or run.get('id') != selected_id or run.get('run_attempt') != attempt:
            raise ValueError('Foreign run attempt response')
    if (str(run.get('path', '')).split('@', 1)[0] != '.github/workflows/ci.yml' or
            run.get('event') not in ('push', 'workflow_dispatch') or
            not isinstance(run.get('head_branch'), str) or not run['head_branch']):
        raise ValueError('Selected history is not an explicit push/manual CI run')
    if run_id is None and (run['event'] != 'push' or run['head_branch'] != 'master'):
        raise ValueError('Default selection is not a master-push CI run')
    if re.fullmatch(r'[0-9a-f]{40}', str(run.get('head_sha', ''))) is None:
        raise ValueError('Invalid selected source SHA')
    _positive(run.get('run_attempt'), 'selected attempt')
    return run


def _artifacts(repo, run, gh):
    """Require exactly one nonexpired artifact per architecture for the explicitly selected attempt."""
    pages = _json(gh(['api', '--paginate', '--slurp',
                     f'repos/{repo}/actions/runs/{run["id"]}/artifacts?per_page=100']))
    if not isinstance(pages, list):
        raise ValueError('Malformed paginated artifact response')
    rows = []
    for page in pages:
        if not isinstance(page, dict) or not isinstance(page.get('artifacts'), list):
            raise ValueError('Malformed artifact page')
        rows.extend(page['artifacts'])
    selected = {}
    for arch in ARCHITECTURES:
        name = f'pvm-performance-{arch}-{run["run_attempt"]}'
        matches = [row for row in rows if isinstance(row, dict) and row.get('name') == name]
        if len(matches) != 1 or matches[0].get('expired') is not False:
            raise ValueError('Missing, duplicate or expired artifact: '+name)
        selected[arch] = matches[0]
    return selected


def _read_report(folder):
    """Read only one bounded canonical report; never execute downloaded commands or binaries."""
    candidates = list(folder.rglob('results.json'))
    matches = []
    for path in candidates:
        if path.is_symlink() or not path.resolve().is_relative_to(folder.resolve()):
            raise ValueError('Redirected artifact report')
        if path.stat().st_size > 32*1024*1024:
            raise ValueError('Unbounded artifact report')
        value = _json(path.read_text())
        if isinstance(value, dict) and value.get('schema') == SCHEMA:
            matches.append(value)
    if len(matches) != 1:
        raise ValueError('Artifact lacks one exact canonical performance report')
    return validate_report(matches[0])


def _retire(folder):
    """Invalidate only this helper's owned views, including old per-architecture green reports."""
    for root in (folder, *(folder/arch for arch in ARCHITECTURES)):
        for name in ('summary.md', 'samples.csv', 'results.json', 'latest.json'):
            (root/name).unlink(missing_ok=True)


def retrieve(repo='jacogr/ragnarok', folder='build/tests/pvm-performance-latest',
             run_id=None, attempt=None, gh=None):
    """Download and atomically expose same-run full reports for both native CPUs, or record failure."""
    gh = _gh if gh is None else gh
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    _retire(folder)
    selected = None
    try:
        selected = select_run(repo, run_id, attempt, gh)
        if run_id is None and attempt is None:
            # A skipped/not-yet-created workflow for a newer merge is not permission to label old data latest.
            reference = _json(gh(['api', f'repos/{repo}/git/ref/heads/master']))
            master = reference.get('object', {}).get('sha')
            if (reference.get('ref') != 'refs/heads/master' or
                    re.fullmatch(r'[0-9a-f]{40}', str(master)) is None):
                raise ValueError('Invalid current master reference')
            if master != selected['head_sha']:
                raise ValueError('Newest master CI run does not yet match current master '+master+
                                 '; no older result substituted')
        if selected.get('status') != 'completed' or selected.get('conclusion') != 'success':
            raise ValueError('Newest/selected master CI run is '+str(selected.get('status'))+'/'+
                             str(selected.get('conclusion'))+'; no older result substituted')
        artifacts = _artifacts(repo, selected, gh)
        reports = {}
        with tempfile.TemporaryDirectory(prefix='pvm-performance-') as temporary:
            for arch in ARCHITECTURES:
                # Name includes attempt; gh never chooses a different run or an older architecture artifact.
                destination = Path(temporary)/arch
                destination.mkdir()
                gh(['run', 'download', str(selected['id']), '--repo', repo, '--name',
                    artifacts[arch]['name'], '--dir', str(destination)])
                report = _read_report(destination)
                ci = report['identity']['ci']
                if (report['architecture'] != arch or report['scope'] != 'all' or
                        report['revision'] != selected['head_sha'] or
                        _positive(ci['GITHUB_RUN_ID'], 'report run ID') != selected['id'] or
                        _positive(ci['GITHUB_RUN_ATTEMPT'], 'report attempt') != selected['run_attempt'] or
                        ci['GITHUB_EVENT_NAME'] != selected['event'] or
                        ci['GITHUB_REF'] != 'refs/heads/'+selected['head_branch'] or
                        ci['GITHUB_REPOSITORY'].lower() != repo.lower()):
                    raise ValueError('Artifact source/run/attempt/architecture/scope disagreement')
                reports[arch] = report
        # Architectures may have different compiler/native binaries, never different source/reference/golden cohorts.
        arm, x86 = (reports[arch]['identity'] for arch in ARCHITECTURES)
        if (arm['reference_revision'] != x86['reference_revision'] or
                arm['doom']['golden_rgba_sha256'] != x86['doom']['golden_rgba_sha256']):
            raise ValueError('Cross-architecture reference/golden identity disagreement')
        summaries = [render_summary(reports[arch]) for arch in ARCHITECTURES]
        for arch in ARCHITECTURES:
            publish_report(reports[arch], folder/arch)
        result = dict(schema='pvm-performance-latest-v1', status='passed', repository=repo,
            revision=selected['head_sha'], run_id=selected['id'], run_attempt=selected['run_attempt'],
            selection='newest-master-push' if run_id is None and attempt is None else 'explicit-history',
            event=selected['event'], ref='refs/heads/'+selected['head_branch'],
            architectures=list(ARCHITECTURES), artifacts={arch: artifacts[arch]['name'] for arch in ARCHITECTURES})
        _atomic_text(folder/'summary.md', 'Same-source native reports; no cross-architecture ratio.\n\n'+
                     '\n'.join(summaries))
        _atomic_text(folder/'latest.json', json.dumps(result, indent=2)+'\n')
        return result
    except BaseException as error:
        # A pending/newer failed run or a partial download must not leave an older successful view.
        _retire(folder)
        result = dict(schema='pvm-performance-latest-v1', status='failed', repository=repo,
                      error=str(error), selected_run=selected)
        _atomic_text(folder/'latest.json', json.dumps(result, indent=2)+'\n')
        raise


def main():
    """Expose authenticated read-only latest/history retrieval without dispatching any workflow."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', default='jacogr/ragnarok')
    parser.add_argument('--output', default='build/tests/pvm-performance-latest')
    parser.add_argument('--run-id', help='Explicit historical CI push/manual run (full reports only)')
    parser.add_argument('--attempt', help='Explicit attempt; default is the selected run latest attempt')
    args = parser.parse_args()
    result = retrieve(args.repo, args.output, args.run_id, args.attempt)
    print(f'PVM performance: {result["revision"]}, run{result["run_id"]}/attempt{result["run_attempt"]}')


if __name__ == '__main__':
    main()
