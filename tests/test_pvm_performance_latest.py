# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Exercise newest-run, exact-attempt and dual-architecture retrieval with an inert gh boundary."""
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
    """Return authenticated-CLI-shaped metadata and local JSON, never native/network commands."""

    def __init__(self):
        """Seed two independent architecture reports and a complete newest master push."""
        self.run = dict(id=100, run_attempt=1, event='push', head_branch='master',
            head_sha=REVISION, path='.github/workflows/ci.yml', status='completed', conclusion='success')
        self.reports = {arch: observations(architecture=arch) for arch in ('arm64', 'x86_64')}
        self.artifacts = [dict(id=index+1, name=f'pvm-performance-{arch}-1', expired=False)
                          for index, arch in enumerate(self.reports)]
        self.downloads = []
        self.duplicate_report = False
        self.old_attempt = None
        self.master_sha = REVISION

    def __call__(self, args):
        """Only metadata reads and explicitly named artifact downloads are admissible operations."""
        if args[0] == 'api':
            endpoint = args[-1]
            if '/workflows/ci.yml/runs?' in endpoint:
                return json.dumps(dict(workflow_runs=[self.run]))
            if endpoint.endswith('/git/ref/heads/master'):
                return json.dumps(dict(ref='refs/heads/master', object=dict(sha=self.master_sha)))
            if '/artifacts?' in endpoint:
                return json.dumps([dict(artifacts=self.artifacts)])
            if '/attempts/' in endpoint:
                return json.dumps(self.old_attempt)
            if endpoint.endswith('/actions/runs/100'):
                return json.dumps(self.run)
        elif args[:2] == ['run', 'download']:
            name = args[args.index('--name')+1]
            destination = Path(args[args.index('--dir')+1])
            arch = next(a for a in self.reports if name.startswith('pvm-performance-'+a+'-'))
            self.downloads.append(name)
            (destination/'results.json').write_text(json.dumps(self.reports[arch]))
            if self.duplicate_report:
                (destination/'nested').mkdir()
                (destination/'nested/results.json').write_text(json.dumps(self.reports[arch]))
            return ''
        raise AssertionError('Unexpected tool/native command: '+repr(args))


class LatestPerformanceTests(unittest.TestCase):
    """Latest selection never replaces failure with an older convenient green cohort."""

    def test_ambiguous_json_and_nonfinite_numbers_refused(self):
        """External duplicate source/status fields and fake numeric constants have no accepted interpretation."""
        for text in ('{"status":"failed","status":"passed"}', '{"cpu_ns":NaN}',
                     '{"nested":{"run_id":1,"run_id":2}}'):
            with self.assertRaises(ValueError):
                _json(text)

    def test_complete_current_reports_are_revalidated_and_published(self):
        """Both same-run native architectures retain their raw evidence under one explicit source."""
        gh = InertGitHub()
        with tempfile.TemporaryDirectory() as directory:
            result = retrieve(folder=directory, gh=gh)
            self.assertEqual((result['status'], result['revision'], result['run_attempt']),
                             ('passed', REVISION, 1))
            self.assertEqual(result['architectures'], ['arm64', 'x86_64'])
            self.assertEqual(set(gh.downloads), {'pvm-performance-arm64-1', 'pvm-performance-x86_64-1'})
            for arch in result['architectures']:
                report = json.loads((Path(directory)/arch/'results.json').read_text())
                self.assertEqual(report['architecture'], arch)
                self.assertEqual(len(report['runs']), 22*3*2)

    def test_pending_failed_and_cancelled_newest_never_download_older_data(self):
        """A new incomplete master attempt retires old successful local views and identifies the new run."""
        for status, conclusion in (('queued', None), ('completed', 'failure'), ('completed', 'cancelled')):
            gh = InertGitHub()
            gh.run.update(status=status, conclusion=conclusion)
            with tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                (folder/'summary.md').write_text('old green')
                (folder/'latest.json').write_text('{"status":"passed"}')
                (folder/'arm64').mkdir()
                (folder/'arm64/results.json').write_text('{"status":"passed"}')
                with self.assertRaises(ValueError):
                    retrieve(folder=folder, gh=gh)
                self.assertFalse(gh.downloads)
                record = json.loads((folder/'latest.json').read_text())
                self.assertEqual(record['status'], 'failed')
                self.assertEqual(record['selected_run']['id'], 100)
                self.assertFalse((folder/'summary.md').exists())
                self.assertFalse((folder/'arm64/results.json').exists())

    def test_missing_expired_duplicate_or_foreign_attempt_artifact(self):
        """Two explicit names from the selected attempt are required; old artifacts cannot fill a gap."""
        changes = (
            lambda gh: gh.artifacts.pop(),
            lambda gh: gh.artifacts[0].update(expired=True),
            lambda gh: gh.artifacts.append(copy.deepcopy(gh.artifacts[0])),
            lambda gh: gh.artifacts[0].update(name='pvm-performance-arm64-2'),
        )
        for mutate in changes:
            gh = InertGitHub()
            mutate(gh)
            with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
                retrieve(folder=directory, gh=gh)

    def test_artifact_source_scope_architecture_run_and_attempt_disagreement(self):
        """Valid individual JSON cannot be reused under another architecture, SHA, run or attempt."""
        changes = (
            lambda r: r.update(architecture='arm64'),
            lambda r: r['identity']['ci'].update(GITHUB_RUN_ATTEMPT='2'),
            lambda r: r['identity']['ci'].update(GITHUB_RUN_ID='101'),
            lambda r: r.update(scope='micro'),
            lambda r: r['identity']['ci'].update(GITHUB_REPOSITORY='foreign/repository'),
        )
        for mutate in changes:
            gh = InertGitHub()
            mutate(gh.reports['x86_64'])
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    retrieve(folder=directory, gh=gh)
                self.assertFalse((Path(directory)/'arm64/results.json').exists())
                self.assertEqual(json.loads((Path(directory)/'latest.json').read_text())['status'], 'failed')
        gh = InertGitHub()
        value = gh.reports['x86_64']
        value.update(revision='e'*40)
        value['identity']['ci']['GITHUB_SHA'] = 'e'*40
        value['identity']['native_qualification']['revision'] = 'e'*40
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
            retrieve(folder=directory, gh=gh)

    def test_cross_architecture_golden_and_partial_report_refused(self):
        """Both reports must describe the same canonical reference/golden and complete case coverage."""
        for mismatch in ('golden', 'partial', 'duplicate-json'):
            gh = InertGitHub()
            if mismatch == 'golden':
                gh.reports['x86_64']['identity']['doom']['golden_rgba_sha256'] = 'e'*64
            elif mismatch == 'partial':
                gh.reports['x86_64']['runs'].pop()
            else:
                gh.duplicate_report = True
            with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
                retrieve(folder=directory, gh=gh)

    def test_explicit_historical_attempt_is_not_mixed_with_current_attempt(self):
        """An older complete attempt requires the explicit option and the matching two artifact names."""
        gh = InertGitHub()
        gh.old_attempt = copy.deepcopy(gh.run)
        gh.run['run_attempt'] = 2
        gh.artifacts += [dict(id=9, name='pvm-performance-arm64-2', expired=False)]
        with tempfile.TemporaryDirectory() as directory:
            value = retrieve(folder=directory, run_id=100, attempt=1, gh=gh)
            self.assertEqual((value['selection'], value['run_attempt']), ('explicit-history', 1))
            self.assertTrue(all(name.endswith('-1') for name in gh.downloads))
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
            retrieve(folder=directory, gh=gh)

    def test_wrong_workflow_and_newer_master_cannot_be_silently_latest(self):
        """Default latest cannot use another workflow, a nonpush event or an older merged source."""
        for field, value in (('path', '.github/workflows/other.yml'),
                             ('event', 'pull_request')):
            gh = InertGitHub()
            gh.run[field] = value
            with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
                retrieve(folder=directory, run_id=100, gh=gh)
        gh = InertGitHub()
        gh.master_sha = 'e'*40
        with tempfile.TemporaryDirectory() as directory, self.assertRaisesRegex(ValueError, 'current master'):
            retrieve(folder=directory, gh=gh)

    def test_manual_full_history_requires_explicit_selection_and_matching_ref(self):
        """A branch qualification can be inspected explicitly without being mislabeled latest master."""
        gh = InertGitHub()
        gh.run.update(event='workflow_dispatch', head_branch='feature')
        for value in gh.reports.values():
            value['identity']['ci'].update(GITHUB_EVENT_NAME='workflow_dispatch',
                                           GITHUB_REF='refs/heads/feature')
        with tempfile.TemporaryDirectory() as directory:
            value = retrieve(folder=directory, run_id=100, gh=gh)
            self.assertEqual((value['selection'], value['ref']), ('explicit-history', 'refs/heads/feature'))
        with tempfile.TemporaryDirectory() as directory, self.assertRaises(ValueError):
            retrieve(folder=directory, gh=gh)


if __name__ == '__main__':
    unittest.main()
