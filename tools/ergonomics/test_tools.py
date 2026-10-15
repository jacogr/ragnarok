#!/usr/bin/env python3
"""Metric-integrity tests use synthetic commands; none are native-language performance/development evidence."""
from pathlib import Path
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import journal
import measure


# Exercise comment recognition rather than counting tokens in quoted protocol URLs as comments.
class LocTests(unittest.TestCase):
    # Nim suffixes and nested comments must not swallow later code or create fake implementation lines.
    def test_nim_comments_and_suffixes(self):
        text = '# header\nlet x = 3\'u64 # inline\n#[ outer\n #[ nested ]#\n]#\nlet s = "# code"\n'
        self.assertEqual(measure.code_lines(text, 'nim'), [False, True, False, False, False, True])

    # Comment delimiters inside source literals retain code, while actual block comments do not.
    def test_odin_and_mojo_literals(self):
        self.assertEqual(measure.code_lines('s := "http://x"\n/* comment\n */\nx := 1 // note', 'odin'), [True, False, False, True])
        self.assertEqual(measure.code_lines('# note\nx = "# string"\n\n', 'mojo'), [False, True, False])

    # Numeric exclusion ranges cannot silently move with changed implementation bytes.
    def test_stale_scope_rejected(self):
        # Use a disposable source so no repository implementation needs to change.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'a.nim').write_text('let a = 1\n')
            # A stale digest must fail before a LOC number is produced.
            with patch.object(measure, 'ROOT', root), self.assertRaises(ValueError):
                measure.snapshot({'files':[{'path':'a.nim','sha256':'stale'}]})


# Synthetic Python subprocesses verify journal accounting independently of the candidates under evaluation.
class JournalTests(unittest.TestCase):
    # Each trial has a fresh synthetic source, explicitly matched checks, and no fabricated real measurements.
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.path = self.root/'trial.json'
        (self.root/'module.nim').write_text('synthetic baseline\n')
        self.ok = [sys.executable, '-c', 'print("synthetic pass")']
        self.bad = [sys.executable, '-c', 'raise SystemExit(1)']
        self.plan = {'equivalence_id':'synthetic-only', 'functionality':'test journal integrity',
                     'specification':'synthetic', 'agent':{'model':'synthetic'},
                     'task_order':['nim','odin','mojo'], 'configuration':{'synthetic':True},
                     'source_paths':{language:['module.nim'] for language in ('nim','odin','mojo')},
                     'acceptance':{'contract':{language:self.ok for language in ('nim','odin','mojo')}},
                     'baseline':{'existing':{language:[sys.executable, '-c', "from pathlib import Path; raise SystemExit(int('broken' in Path('module.nim').read_text()))"] for language in ('nim','odin','mojo')}}}
        self.root_patch = patch.object(journal, 'ROOT', self.root)
        self.environment_patch = patch.object(journal, 'environment', return_value={'synthetic':True})
        self.root_patch.start(); self.environment_patch.start()
        self.addCleanup(self.root_patch.stop); self.addCleanup(self.environment_patch.stop)
        self.state = journal.begin(self.path, self.plan, 'nim')

    # Keep command details identical across the success/failure accounting scenarios.
    def run_attempt(self, phase, command=None, repair=None, check=None):
        return journal.run(self.path, self.state, phase, check, command or [], 'unknown', repair, 5, 'synthetic fix' if repair else None)

    # Intentional rejection probes and unreviewed manual histories must never manufacture repair/defect zeros.
    def test_unknown_coverage_and_intentional_probe(self):
        self.run_attempt('diagnostic', self.bad)
        self.run_attempt('compile', self.ok)
        self.run_attempt('acceptance', check='contract')
        metrics = journal.finish(self.path, self.state, False)
        self.assertIsNone(metrics['compiler_repair_iterations'])
        self.assertIsNone(metrics['time_to_passing_tests_seconds'])
        self.assertIsNone(metrics['bugs_found_after_compilation'])
        self.assertIsNone(metrics['human_interventions'])
        self.assertIsNone(metrics['regression_rate'])
        self.assertEqual(metrics['direct_compile_invocations'], 1)

    # One actual source-fix cycle remains separate from cause attribution and repeated unchanged compile attempts.
    def test_repair_and_cause(self):
        failed = self.run_attempt('compile', self.bad)
        self.run_attempt('compile', self.bad)
        (self.root/'module.nim').write_text('synthetic repaired source\n')
        self.run_attempt('compile', self.ok, repair=failed['id'])
        journal.annotate(self.path, self.state, 'attribution', 'why', 'ffi', 'synthetic FFI fix', 'synthetic', failed['id'])
        self.run_attempt('acceptance', check='contract')
        metrics = journal.finish(self.path, self.state, True, True)
        self.assertEqual(metrics['compiler_repair_iterations'], 1)
        self.assertEqual(metrics['observed_compiler_repairs_by_cause']['ffi'], 1)
        self.assertEqual(metrics['bugs_found_after_compilation'], 0)
        self.assertIsNone(metrics['regression_rate'])

    # A passing result from earlier bytes cannot authorize completion after another edit.
    def test_stale_acceptance_rejected(self):
        self.run_attempt('compile', self.ok)
        self.run_attempt('acceptance', check='contract')
        (self.root/'module.nim').write_text('later edit\n')
        # Completion must reject acceptance from the old source bytes.
        with self.assertRaises(ValueError):
            journal.finish(self.path, self.state, True, True)

    # Check-level regression denominators require actual baseline passes and post-change reruns.
    def test_regression_evidence_and_denominator(self):
        # A failed rerun cannot establish its own previously passing baseline.
        with self.assertRaises(ValueError):
            self.run_attempt('recheck', check='existing')
        self.run_attempt('baseline', check='existing')
        self.run_attempt('compile', self.ok)
        (self.root/'module.nim').write_text('synthetic broken source\n')
        self.run_attempt('compile', self.ok)
        failed = self.run_attempt('recheck', check='existing')
        journal.annotate(self.path, self.state, 'regression', 'reg', 'language', 'synthetic regression', 'synthetic', failed['id'])
        self.run_attempt('acceptance', check='contract')
        metrics = journal.finish(self.path, self.state, True, True)
        self.assertEqual(metrics['regression_rate'], 1)
        self.assertEqual(metrics['baseline_checks_retested'], 1)

    # Absent tool executables must not become fake compiler rejections or unfinished invisible attempts.
    def test_missing_compiler_is_infrastructure(self):
        event = self.run_attempt('compile', ['/nonexistent/synthetic-tool'])
        self.assertEqual(event['status'], 'launch_error')
        self.assertEqual(event['cause'], 'infrastructure')
        self.assertFalse(event['launched'])

    # Repeated green runs are validation, not extra development time before the first green frontier.
    def test_time_uses_first_complete_acceptance(self):
        self.run_attempt('compile', self.ok)
        first = self.run_attempt('acceptance', check='contract')
        self.run_attempt('acceptance', check='contract')
        journal.finish(self.path, self.state, True, True)
        self.assertEqual(self.state['first_passing_tests_at'], first['ended_at'])

    # Source/test exclusions are reviewed separately; the journal must reject a stale LOC count.
    def test_loc_snapshot_matches_current_registered_sources(self):
        self.run_attempt('compile', self.ok)
        self.run_attempt('acceptance', check='contract')
        audit = self.root/'loc.json'
        data = {'definition':'synthetic scope', 'files':[{'language':'nim', 'path':'module.nim',
                'sha256':'wrong', 'implementation_loc':1}]}
        audit.write_text(json.dumps(data))
        # An unrelated LOC digest must not authorize a measured implementation count.
        with self.assertRaises(ValueError):
            journal.finish(self.path, self.state, True, True, audit)
        data['files'][0]['sha256'] = self.state['initial_sources']['module.nim']
        audit.write_text(json.dumps(data))
        metrics = journal.finish(self.path, self.state, True, True, audit)
        self.assertEqual(metrics['implementation_loc'], 1)

    # Plans and deliberate rejection probes cannot be rewritten to invent repair cycles.
    def test_plan_and_repair_provenance(self):
        probe = self.run_attempt('diagnostic', self.bad)
        # An intentional negative probe must never become a repair numerator.
        with self.assertRaises(ValueError):
            self.run_attempt('compile', self.ok, repair=probe['id'])
        changed = copy.deepcopy(self.state)
        changed['plan']['functionality'] = 'different task'
        # The journal must reject a changed registered contract.
        with self.assertRaises(ValueError):
            journal.save(self.path, changed)

    # Standard CLI options must parse before the explicit command separator.
    def test_cli_compiler_command(self):
        # The subprocess resolves its real repository root; use an existing read-only project source.
        state = copy.deepcopy(self.state)
        state['plan']['source_paths'] = {language:['AGENTS.md'] for language in ('nim','odin','mojo')}
        state['plan_sha256'] = journal.hashlib.sha256(json.dumps(state['plan'], sort_keys=True).encode()).hexdigest()
        journal.save(self.path, state)
        command = [sys.executable, str(Path(journal.__file__)), 'run', '--state', str(self.path),
                   '--phase', 'compile', '--', *self.ok]
        run = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(self.path.read_text())['events'][-1]['status'], 'passed')


# Direct execution performs only synthetic bookkeeping tests and temporary-file operations.
if __name__ == '__main__':
    unittest.main()
