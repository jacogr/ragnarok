#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Retrieve the latest PVM job executions within one source-bound CI run or attempt limit.

Default selection is the newest master-push CI run, including pending or failed runs: an older
green result is never substituted. Selective reruns retain each CPU's actual measurement attempt;
workflow conclusion and successful PVM measurements are reported separately. Authenticated gh
owns API access and artifact downloads.
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


def _rows(endpoint, field, gh):
    """Read all metadata pages; malformed or omitted pages cannot silently remove newer evidence."""
    pages = _json(gh(['api', '--paginate', '--slurp', endpoint]))
    if not isinstance(pages, list) or not pages:
        raise ValueError('Malformed paginated '+field+' response')
    rows = []
    for page in pages:
        if (not isinstance(page, dict) or not isinstance(page.get(field), list) or
                any(not isinstance(row, dict) for row in page[field])):
            raise ValueError('Malformed '+field+' page')
        rows.extend(page[field])
    return rows


def _artifacts(repo, run, gh):
    """Choose newest available artifacts within the limit, pending verification against actual jobs."""
    rows = _rows(f'repos/{repo}/actions/runs/{run["id"]}/artifacts?per_page=100', 'artifacts', gh)
    limit = _positive(run['run_attempt'], 'selected attempt limit')
    selected = {}
    for arch in ARCHITECTURES:
        # Expired/duplicate newest artifacts are failures, never permission to choose older green.
        candidates = []
        for row in rows:
            match = re.fullmatch('pvm-performance-'+arch+r'-([1-9][0-9]*)', str(row.get('name', '')))
            if match is not None and int(match[1]) <= limit:
                candidates.append((int(match[1]), row))
        if not candidates:
            raise ValueError('Missing PVM artifact for '+arch+' within attempt '+str(limit))
        newest = max(number for number, _ in candidates)
        matches = [row for number, row in candidates if number == newest]
        if len(matches) != 1 or matches[0].get('expired') is not False:
            raise ValueError('Duplicate or expired newest artifact for '+arch)
        _positive(matches[0].get('id'), 'artifact ID')
        selected[arch] = dict(matches[0], measurement_attempt=newest)
    return selected


def _jobs(repo, run, reports, gh):
    """Find each report-declared job's latest execution, including failures that forbid fallback."""
    names = {arch: reports[arch]['identity']['ci']['PVM_CI_JOB_NAME'] for arch in ARCHITECTURES}
    if len(set(names.values())) != len(ARCHITECTURES):
        raise ValueError('Ambiguous PVM architecture job names')
    selected = {}
    for attempt in range(_positive(run['run_attempt'], 'job attempt limit'), 0, -1):
        rows = _rows(f'repos/{repo}/actions/runs/{run["id"]}/attempts/{attempt}/jobs?per_page=100',
                     'jobs', gh)
        for arch, name in names.items():
            if arch in selected:
                continue  # An earlier execution can never override the newest one already selected.
            matches = []
            for row in rows:
                if row.get('name') != name:
                    continue  # Other jobs cannot supply identity or status for this architecture.
                if 'run_attempt' in row:
                    actual = _positive(row['run_attempt'], 'actual PVM job attempt')
                    if actual > attempt:
                        raise ValueError('PVM job belongs to a future attempt')
                    if actual < attempt:
                        continue  # Some API views carry earlier jobs; inspect their real attempt below.
                matches.append(row)
            if not matches:
                continue  # A selective rerun of unrelated jobs leaves this CPU's execution unchanged.
            if len(matches) != 1:
                raise ValueError('Duplicate PVM job for '+arch+' in attempt '+str(attempt))
            job = matches[0]
            identifier = _positive(job.get('id'), 'PVM job ID')
            if job.get('run_id') != run['id'] or job.get('head_sha') != run['head_sha']:
                raise ValueError('PVM job source/run disagreement')
            if job.get('status') != 'completed' or job.get('conclusion') != 'success':
                raise ValueError('Latest '+arch+' PVM execution is '+str(job.get('status'))+'/'+
                                 str(job.get('conclusion'))+' in attempt '+str(attempt))
            ci = reports[arch]['identity']['ci']
            if _positive(ci['GITHUB_RUN_ATTEMPT'], 'measurement attempt') != attempt:
                raise ValueError('Latest '+arch+' PVM execution has no matching measurement artifact')
            selected[arch] = dict(id=identifier, name=name, run_attempt=attempt,
                                  status=job['status'], conclusion=job['conclusion'])
        if len(selected) == len(ARCHITECTURES):
            break  # All newer attempts have been checked; older executions are irrelevant.
    if len(selected) != len(ARCHITECTURES):
        raise ValueError('Missing PVM job execution for one or both architectures')
    if len({job['id'] for job in selected.values()}) != len(ARCHITECTURES):
        raise ValueError('One PVM job cannot identify two native architectures')
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
    """Expose each CPU's latest successful PVM execution in the selected source/run, or fail closed."""
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
        if selected.get('status') != 'completed':
            raise ValueError('Newest/selected master CI run is '+str(selected.get('status'))+'/'+
                             str(selected.get('conclusion'))+'; no older result substituted')
        if not isinstance(selected.get('conclusion'), str) or not selected['conclusion'].strip():
            raise ValueError('Completed workflow has no conclusion')
        artifacts = _artifacts(repo, selected, gh)
        reports = {}
        with tempfile.TemporaryDirectory(prefix='pvm-performance-') as temporary:
            for arch in ARCHITECTURES:
                # Exact names bind downloaded evidence to its real producing attempt, not the workflow counter.
                destination = Path(temporary)/arch
                destination.mkdir()
                gh(['run', 'download', str(selected['id']), '--repo', repo, '--name',
                    artifacts[arch]['name'], '--dir', str(destination)])
                report = _read_report(destination)
                ci = report['identity']['ci']
                if (report['architecture'] != arch or report['scope'] != 'all' or
                        report['revision'] != selected['head_sha'] or
                        _positive(ci['GITHUB_RUN_ID'], 'report run ID') != selected['id'] or
                        _positive(ci['GITHUB_RUN_ATTEMPT'], 'report attempt') !=
                        artifacts[arch]['measurement_attempt'] or
                        ci['GITHUB_EVENT_NAME'] != selected['event'] or
                        ci['GITHUB_REF'] != 'refs/heads/'+selected['head_branch'] or
                        ci['GITHUB_REPOSITORY'].lower() != repo.lower()):
                    raise ValueError('Artifact source/run/attempt/architecture/scope disagreement')
                reports[arch] = report
        jobs = _jobs(repo, selected, reports, gh)
        # Architectures may have different compiler/native binaries, never different source/reference/golden cohorts.
        arm, x86 = (reports[arch]['identity'] for arch in ARCHITECTURES)
        if (arm['reference_revision'] != x86['reference_revision'] or
                arm['doom']['golden_rgba_sha256'] != x86['doom']['golden_rgba_sha256']):
            raise ValueError('Cross-architecture reference/golden identity disagreement')
        summaries = [render_summary(reports[arch]) for arch in ARCHITECTURES]
        for arch in ARCHITECTURES:
            publish_report(reports[arch], folder/arch)
        result = dict(schema='pvm-performance-latest-v1', status='passed', repository=repo,
            measurement_schema=SCHEMA, code_lifetime=arm['code_lifetime'],
            revision=selected['head_sha'], run_id=selected['id'], run_attempt=selected['run_attempt'],
            selection='newest-master-push' if run_id is None and attempt is None else 'explicit-history',
            event=selected['event'], ref='refs/heads/'+selected['head_branch'],
            workflow_status=selected['status'], workflow_conclusion=selected['conclusion'],
            measurement_attempts={arch: jobs[arch]['run_attempt'] for arch in ARCHITECTURES},
            jobs=jobs, architectures=list(ARCHITECTURES),
            artifacts={arch: artifacts[arch]['name'] for arch in ARCHITECTURES},
            artifact_ids={arch: artifacts[arch]['id'] for arch in ARCHITECTURES})
        provenance = ('PVM measurements: passed. Source '+selected['head_sha']+', run '+
                      str(selected['id'])+'. Selected workflow attempt '+str(selected['run_attempt'])+
                      ': '+selected['status']+'/'+selected['conclusion']+'.\n\n')
        for arch in ARCHITECTURES:
            provenance += (arch+': measurement attempt '+str(jobs[arch]['run_attempt'])+
                           ', job '+str(jobs[arch]['id'])+', artifact '+str(artifacts[arch]['id'])+'.\n\n')
        _atomic_text(folder/'summary.md', provenance+
                     'Same-source native reports; no cross-architecture ratio.\n\n'+'\n'.join(summaries))
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
    parser.add_argument('--attempt', help='Historical attempt limit; use each CPU\'s latest PVM execution at or before it')
    args = parser.parse_args()
    result = retrieve(args.repo, args.output, args.run_id, args.attempt)
    print(f'PVM performance passed: {result["revision"]}, run{result["run_id"]}; '
          f'workflow attempt{result["run_attempt"]} {result["workflow_conclusion"]}')
    for arch in ARCHITECTURES:
        print(f'{arch}: measurement attempt{result["measurement_attempts"][arch]}, '
              f'job{result["jobs"][arch]["id"]}, artifact{result["artifact_ids"][arch]}')


if __name__ == '__main__':
    main()
