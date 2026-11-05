# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise latest PVM executions across selective reruns with an inert authenticated gh boundary."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from pvm_performance_latest import retrieve, _json
from pvm_performance_fixtures import observations, REVISION


class InertGitHub:
    """Return CLI-shaped metadata and local reports without network, native commands or CI dispatch."""

    def __init__(self):
        """Seed two independent architecture reports and matching actual workflow job executions."""
        self.run = dict(id=100, run_attempt=1, event='push', head_branch='master',
            head_sha=REVISION, path='.github/workflows/ci.yml', status='completed', conclusion='success')
        self.reports = {arch: observations(architecture=arch) for arch in ('arm64', 'x86_64')}
        self.artifacts = [dict(id=index+1, name=f'pvm-performance-{arch}-1', expired=False)
                          for index, arch in enumerate(self.reports)]
        self.jobs = {1: [self.job(arch, 1) for arch in self.reports]}
        self.additional_reports = {}
        self.artifact_pages = None
        self.job_pages = {}
        self.downloads = []
        self.duplicate_report = False
        self.old_attempt = None
        self.master_sha = REVISION

    def job(self, arch, attempt, status='completed', conclusion='success'):
        """Author job metadata independently of the retrieval algorithm and its presentation choices."""
        return dict(id=1000+attempt*10+list(self.reports).index(arch), run_id=100,
            run_attempt=attempt,
            head_sha=REVISION, name=self.reports[arch]['identity']['ci']['PVM_CI_JOB_NAME'],
            status=status, conclusion=conclusion)

    def retry(self, arch, attempt=2, status='completed', conclusion='success', artifact=True):
        """Record a real CPU retry; retaining old artifacts must never conceal its newer outcome."""
        self.run['run_attempt'] = max(self.run['run_attempt'], attempt)
        job = self.job(arch, attempt, status, conclusion)
        self.jobs.setdefault(attempt, []).append(job)
        if artifact:
            report = observations(architecture=arch, attempt=str(attempt))
            report['identity']['ci']['PVM_CI_JOB_NAME'] = job['name']
            self.additional_reports[arch, attempt] = report
            self.artifacts.append(dict(id=max(row['id'] for row in self.artifacts)+1,
                name=f'pvm-performance-{arch}-{attempt}', expired=False))
        return job

    def unrelated_retry(self, attempt=2):
        """Only Unit executes again; previously successful PVM processes and artifacts stay unchanged."""
        self.run['run_attempt'] = attempt
        self.jobs[attempt] = [dict(id=9000+attempt, run_id=100, head_sha=REVISION,
                                  name='Independent unrelated unit job', status='completed', conclusion='success')]

    def __call__(self, args):
        """Admit only metadata reads and explicitly named artifact downloads to temporary directories."""
        if args[0] == 'api':
            endpoint = args[-1]
            if '/workflows/ci.yml/runs?' in endpoint:
                return json.dumps(dict(workflow_runs=[self.run]))
            if endpoint.endswith('/git/ref/heads/master'):
                return json.dumps(dict(ref='refs/heads/master', object=dict(sha=self.master_sha)))
            if '/artifacts?' in endpoint:
                return json.dumps(self.artifact_pages if self.artifact_pages is not None else
                                  [dict(artifacts=self.artifacts)])
            if '/attempts/' in endpoint and '/jobs?' in endpoint:
                attempt = int(endpoint.split('/attempts/')[1].split('/')[0])
                return json.dumps(self.job_pages.get(attempt, [dict(jobs=self.jobs.get(attempt, []))]))
            if '/attempts/' in endpoint:
                attempt = int(endpoint.rsplit('/', 1)[1])
                return json.dumps(self.old_attempt if self.old_attempt is not None else
                                  dict(self.run, run_attempt=attempt))
            if endpoint.endswith('/actions/runs/100'):
                return json.dumps(self.run)
        elif args[:2] == ['run', 'download']:
            name = args[args.index('--name')+1]
            destination = Path(args[args.index('--dir')+1])
            arch = next(a for a in self.reports if name.startswith('pvm-performance-'+a+'-'))
            attempt = int(name.rsplit('-', 1)[1])
            report = self.reports[arch] if attempt == 1 else self.additional_reports[arch, attempt]
            self.downloads.append(name)
            (destination/'results.json').write_text(json.dumps(report))
            if self.duplicate_report:
                (destination/'nested').mkdir()
                (destination/'nested/results.json').write_text(json.dumps(report))
            return ''
        raise AssertionError('Unexpected tool/native command: '+repr(args))


class LatestPerformanceTests(unittest.TestCase):
    """Latest means newest actual PVM executions on this source/run, including blocking failures."""

    def assert_refused_without_stale_views(self, gh):
        """Every failure retires the helper's old green root and both architecture views."""
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for root in (folder, folder/'arm64', folder/'x86_64'):
                root.mkdir(exist_ok=True)
                for name in ('results.json', 'summary.md', 'samples.csv'):
                    (root/name).write_text('old green')
            with self.assertRaises(ValueError):
                retrieve(folder=folder, gh=gh)
            record = json.loads((folder/'latest.json').read_text())
            self.assertEqual(record['status'], 'failed')
            self.assertEqual(record['selected_run']['id'], 100)
            for root in (folder, folder/'arm64', folder/'x86_64'):
                self.assertFalse(any((root/name).exists() for name in
                                     ('results.json', 'summary.md', 'samples.csv')))

    def test_ambiguous_json_and_nonfinite_numbers_refused(self):
        """External duplicate source/status fields and fake numeric constants have no accepted interpretation."""
        for text in ('{"status":"failed","status":"passed"}', '{"cpu_ns":NaN}',
                     '{"nested":{"run_id":1,"run_id":2}}'):
            with self.assertRaises(ValueError):
                _json(text)

    def test_complete_current_reports_are_revalidated_and_published(self):
        """Both native CPUs preserve full raw coverage and actual job/artifact/attempt provenance."""
        gh = InertGitHub()
        with tempfile.TemporaryDirectory() as directory:
            result = retrieve(folder=directory, gh=gh)
            self.assertEqual((result['status'], result['revision'], result['run_attempt']),
                             ('passed', REVISION, 1))
            self.assertEqual(result['architectures'], ['arm64', 'x86_64'])
            self.assertEqual(result['measurement_attempts'], dict(arm64=1, x86_64=1))
            self.assertEqual(result['workflow_conclusion'], 'success')
            self.assertEqual(set(gh.downloads), {'pvm-performance-arm64-1', 'pvm-performance-x86_64-1'})
            for arch in result['architectures']:
                report = json.loads((Path(directory)/arch/'results.json').read_text())
                self.assertEqual(report['architecture'], arch)
                self.assertEqual(len(report['runs']), 22*3*2)
                self.assertEqual(result['jobs'][arch]['id'], gh.job(arch, 1)['id'])
                self.assertEqual(result['jobs'][arch]['name'], report['identity']['ci']['PVM_CI_JOB_NAME'])
            self.assertEqual(result['artifact_ids'], dict(arm64=1, x86_64=2))

    def test_unrelated_failure_and_unit_only_retry_preserve_successful_pvm_evidence(self):
        """Overall red is visible separately, and retrying Unit does not require expensive CPU reruns."""
        for attempt, conclusion in ((1, 'failure'), (1, 'cancelled'), (2, 'success'), (2, 'failure')):
            gh = InertGitHub()
            if attempt == 2:
                gh.unrelated_retry()
            gh.run['conclusion'] = conclusion
            with self.subTest(attempt=attempt, conclusion=conclusion), tempfile.TemporaryDirectory() as directory:
                result = retrieve(folder=directory, gh=gh)
                self.assertEqual((result['status'], result['run_attempt'], result['workflow_conclusion']),
                                 ('passed', attempt, conclusion))
                self.assertEqual(result['measurement_attempts'], dict(arm64=1, x86_64=1))
                self.assertTrue(all(name.endswith('-1') for name in gh.downloads))
                # Human-facing output must preserve the red workflow as well as measurement provenance.
                summary = (Path(directory)/'summary.md').read_text()
                self.assertIn('completed/'+conclusion, summary)
                self.assertIn('measurement attempt 1', summary)

    def test_single_cpu_retry_uses_each_actual_attempt(self):
        """A successful x86 retry can join untouched ARM evidence on the exact same source/run."""
        gh = InertGitHub()
        gh.retry('x86_64')
        with tempfile.TemporaryDirectory() as directory:
            result = retrieve(folder=directory, gh=gh)
            self.assertEqual(result['measurement_attempts'], dict(arm64=1, x86_64=2))
            self.assertEqual(set(gh.downloads), {'pvm-performance-arm64-1', 'pvm-performance-x86_64-2'})
            for arch, attempt in result['measurement_attempts'].items():
                report = json.loads((Path(directory)/arch/'results.json').read_text())
                self.assertEqual(report['identity']['ci']['GITHUB_RUN_ATTEMPT'], str(attempt))

    def test_pending_workflow_and_newer_unsuccessful_pvm_never_reuse_old_green(self):
        """New PVM failures, cancellation, skips and in-progress retries all block previous success."""
        for status in ('queued', 'in_progress'):
            gh = InertGitHub()
            gh.run.update(status=status, conclusion=None)
            self.assert_refused_without_stale_views(gh)
            self.assertFalse(gh.downloads)
        for status, conclusion in (('queued', None), ('in_progress', None), ('completed', 'failure'),
                                   ('completed', 'cancelled'), ('completed', 'skipped'), ('completed', 'timed_out')):
            for artifact in (True, False):
                gh = InertGitHub()
                gh.retry('x86_64', status=status, conclusion=conclusion, artifact=artifact)
                gh.run['conclusion'] = 'failure'
                with self.subTest(status=status, conclusion=conclusion, artifact=artifact):
                    self.assert_refused_without_stale_views(gh)

    def test_missing_expired_duplicate_or_deleted_newest_artifact(self):
        """Deleting a newer artifact cannot make an older successful PVM execution latest again."""
        changes = (
            lambda gh: gh.artifacts.pop(),
            lambda gh: gh.artifacts[0].update(expired=True),
            lambda gh: gh.artifacts.append(copy.deepcopy(gh.artifacts[0])),
            lambda gh: gh.retry('arm64', artifact=False),
        )
        for mutate in changes:
            gh = InertGitHub()
            mutate(gh)
            self.assert_refused_without_stale_views(gh)
        for invalid in ('expired', 'duplicate'):
            gh = InertGitHub()
            gh.retry('arm64')
            if invalid == 'expired':
                gh.artifacts[-1]['expired'] = True
            else:
                gh.artifacts.append(copy.deepcopy(gh.artifacts[-1]))
            self.assert_refused_without_stale_views(gh)

    def test_job_identity_pagination_and_cosmetic_names(self):
        """Names are source-bound receipt data; all metadata pages count, independent of presentation."""
        gh = InertGitHub()
        for index, arch in enumerate(gh.reports):
            name = 'Renamed comparison presentation ['+arch+']'
            gh.reports[arch]['identity']['ci']['PVM_CI_JOB_NAME'] = name
            gh.jobs[1][index]['name'] = name
        gh.unrelated_retry()
        gh.artifact_pages = [dict(artifacts=[row]) for row in gh.artifacts]
        gh.job_pages[1] = [dict(jobs=[row]) for row in gh.jobs[1]]
        with tempfile.TemporaryDirectory() as directory:
            result = retrieve(folder=directory, gh=gh)
            self.assertEqual(result['measurement_attempts'], dict(arm64=1, x86_64=1))
            self.assertEqual({row['name'] for row in result['jobs'].values()},
                             {row['name'] for row in gh.jobs[1]})

    def test_missing_ambiguous_foreign_or_malformed_job_metadata(self):
        """Neither an ambiguous name nor another source/run/job can certify a measurement process."""
        changes = (
            lambda gh: gh.jobs[1].pop(),
            lambda gh: gh.jobs[1].append(copy.deepcopy(gh.jobs[1][0])),
            lambda gh: gh.jobs[1][0].update(run_id=101),
            lambda gh: gh.jobs[1][0].update(head_sha='e'*40),
            lambda gh: gh.jobs[1][0].update(id=0),
            lambda gh: gh.jobs[1][0].update(run_attempt=0),
            lambda gh: gh.jobs[1][0].update(run_attempt=2),
            lambda gh: gh.jobs[1][0].update(id=gh.jobs[1][1]['id']),
            lambda gh: gh.reports['arm64']['identity']['ci'].update(
                PVM_CI_JOB_NAME=gh.reports['x86_64']['identity']['ci']['PVM_CI_JOB_NAME']),
            lambda gh: gh.job_pages.update({1: [dict(jobs='malformed')]}),
            lambda gh: gh.job_pages.update({1: [dict(jobs=[gh.jobs[1][0]]), dict(jobs=gh.jobs[1])]}),
        )
        for mutate in changes:
            gh = InertGitHub()
            mutate(gh)
            self.assert_refused_without_stale_views(gh)

        # Missing newer metadata cannot certify that a retry left the earlier PVM jobs untouched.
        gh = InertGitHub()
        gh.unrelated_retry()
        gh.job_pages[2] = []
        self.assert_refused_without_stale_views(gh)

    def test_carried_forward_job_metadata_keeps_actual_attempt(self):
        """Inherited jobs in a later API view are not executions of that later workflow attempt."""
        gh = InertGitHub()
        gh.unrelated_retry()
        gh.jobs[2] += copy.deepcopy(gh.jobs[1])
        with tempfile.TemporaryDirectory() as directory:
            value = retrieve(folder=directory, gh=gh)
            self.assertEqual(value['run_attempt'], 2)
            self.assertEqual(value['measurement_attempts'], dict(arm64=1, x86_64=1))
        # An actual newer execution wins even if the view also contains its previous incarnation.
        gh = InertGitHub()
        gh.retry('x86_64')
        gh.jobs[2] += copy.deepcopy(gh.jobs[1])
        with tempfile.TemporaryDirectory() as directory:
            value = retrieve(folder=directory, gh=gh)
            self.assertEqual(value['measurement_attempts'], dict(arm64=1, x86_64=2))

    def test_artifact_source_scope_architecture_run_and_attempt_disagreement(self):
        """Valid JSON cannot be reused for another CPU, attempt, CI job, repository or source."""
        changes = (
            lambda r: r.update(architecture='arm64'),
            lambda r: r['identity']['ci'].update(GITHUB_RUN_ATTEMPT='2'),
            lambda r: r['identity']['ci'].update(GITHUB_RUN_ID='101'),
            lambda r: r['identity']['ci'].update(GITHUB_JOB='foreign-job'),
            lambda r: r['identity']['ci'].pop('PVM_CI_JOB_NAME'),
            lambda r: r.update(scope='micro'),
            lambda r: r['identity']['ci'].update(GITHUB_REPOSITORY='foreign/repository'),
        )
        for mutate in changes:
            gh = InertGitHub()
            mutate(gh.reports['x86_64'])
            self.assert_refused_without_stale_views(gh)
        gh = InertGitHub()
        value = gh.reports['x86_64']
        value.update(revision='e'*40)
        value['identity']['ci'].update(GITHUB_SHA='e'*40)
        value['identity']['native_qualification']['revision'] = 'e'*40
        self.assert_refused_without_stale_views(gh)

    def test_cross_architecture_golden_and_partial_report_refused(self):
        """Reports still require identical reference/golden and all full-matrix cells after reruns."""
        for mismatch in ('golden', 'partial', 'duplicate-json'):
            gh = InertGitHub()
            if mismatch == 'golden':
                gh.reports['x86_64']['identity']['doom']['golden_rgba_sha256'] = 'e'*64
            elif mismatch == 'partial':
                gh.reports['x86_64']['runs'].pop()
            else:
                gh.duplicate_report = True
            self.assert_refused_without_stale_views(gh)

    def test_explicit_attempt_is_historical_execution_limit(self):
        """History may combine earlier actual CPU attempts but cannot see executions beyond its limit."""
        gh = InertGitHub()
        gh.retry('x86_64', attempt=2)
        gh.retry('arm64', attempt=3, conclusion='failure')
        gh.old_attempt = dict(gh.run, run_attempt=2, conclusion='failure')
        with tempfile.TemporaryDirectory() as directory:
            value = retrieve(folder=directory, run_id=100, attempt=2, gh=gh)
            self.assertEqual((value['selection'], value['run_attempt'], value['workflow_conclusion']),
                             ('explicit-history', 2, 'failure'))
            self.assertEqual(value['measurement_attempts'], dict(arm64=1, x86_64=2))
        self.assert_refused_without_stale_views(gh)

    def test_wrong_workflow_and_newer_master_cannot_be_silently_latest(self):
        """Default latest cannot use another workflow, a nonpush event or an older merged source."""
        for field, value in (('path', '.github/workflows/other.yml'), ('event', 'pull_request')):
            gh = InertGitHub()
            gh.run[field] = value
            with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
                retrieve(folder=directory, run_id=100, gh=gh)
        gh = InertGitHub()
        gh.master_sha = 'e'*40
        self.assert_refused_without_stale_views(gh)

    def test_manual_full_history_requires_explicit_selection_and_matching_ref(self):
        """Explicit branch qualification uses the same actual-job selection without becoming latest master."""
        gh = InertGitHub()
        gh.run.update(event='workflow_dispatch', head_branch='feature')
        for value in gh.reports.values():
            value['identity']['ci'].update(GITHUB_EVENT_NAME='workflow_dispatch', GITHUB_REF='refs/heads/feature')
        with tempfile.TemporaryDirectory() as directory:
            value = retrieve(folder=directory, run_id=100, gh=gh)
            self.assertEqual((value['selection'], value['ref']), ('explicit-history', 'refs/heads/feature'))
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
            retrieve(folder=directory, gh=gh)


if __name__ == '__main__':
    unittest.main()
