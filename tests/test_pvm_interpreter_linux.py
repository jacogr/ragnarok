# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Reject incomplete, foreign or inconsistent lifecycle evidence before publishing Linux timings."""
import importlib.util
from pathlib import Path
import unittest
import textwrap
import tempfile
from unittest.mock import Mock, patch
from workflow_fixtures import event_context, expression, job_condition, job_section, family_section

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('interpreter_linux',ROOT/'tools/pvm_interpreter_compare.py')
comparison = importlib.util.module_from_spec(spec)
spec.loader.exec_module(comparison)


def kernel():
    """Supply a complete constructor and thirteen exact additive lifecycle records."""
    return 'PHASE_PREPARE,sieve,10,20\n'+''.join(
        f'PHASE,sieve,{i},1,100,2,103\nPHASE_CACHE,sieve,{i},13938,27482,1166742\n' for i in range(13))


def doom():
    """Supply complete outer-call, nested phase and host/publication diagnostic evidence."""
    lines = ['DOOM_PREPARE,tick,10,20,533657,4285']
    for i in range(13):
        # Fine-grained subclocks are explicitly distinct from the actual outer call duration.
        lines += [f'DOOM_RESIDENT,tick,{i},1,2,3',
                  f'DOOM_SAMPLE,prepared,tick,{i},100,101',
                  f'DOOM_PHASE,tick,{i},1,70,20,5,2,1,12180040,10759']
    return '\n'.join(lines)+'\nDOOM_OK,prepared,tick,1024005\n'


class InterpreterLinuxTests(unittest.TestCase):
    def test_complete_lifecycle_and_outer_call_scopes(self):
        """Cold/reused records retain exact constructor, reset, outer-call and publication scopes."""
        parsed = comparison.parse_candidate(kernel(),'sieve')
        self.assertEqual(parsed['preparation_ns'],[10,20])
        self.assertEqual([x['sample'] for x in parsed['samples']],list(range(13)))
        parsed = comparison.parse_candidate(doom(),'tick',True,1024005)
        self.assertEqual(parsed['samples'][0]['lifecycle_ns'],103)
        self.assertEqual(parsed['samples'][0]['cpu_ns'],100)
        self.assertEqual(parsed['samples'][0]['attempts'],12180040)

    def test_refuse_partial_reordered_tampered_and_extra_output(self):
        """A positive child exit cannot stand in for complete strictly framed measurement evidence."""
        for output,case,large in ((kernel(),'sieve',False),(doom(),'tick',True)):
            variants = [output.replace(',0,',',1,',1), output+'unexpected\n',
                        output.replace('PREPARE','FOREIGN',1), '\n'.join(output.splitlines()[:-2])]
            if not large:
                variants += [output.replace(',103',',104',1),output.replace(',100,',',0,',1)]
            else:
                variants += [output.replace('1024005','1024006'),output.replace(',0,100,101',',0,0,101')]
            for variant in variants:
                # Each changed field must independently prevent a successful aggregate/table.
                with self.subTest(case=case,output=variant[:100]), self.assertRaises(ValueError):
                    comparison.parse_candidate(variant,case,large,1024005)

    def test_public_prepared_constructor_and_cache_framing(self):
        """Reusable public owners must retain cold construction and every ordered cache/sample record."""
        output = 'PREPARED_PROGRAM,10,20,100,30\n'+''.join(
            f'SIEVE,ragnarok_prepared,100000,{i},101,100\nPREPARED_CACHE,{i},3,6,100,200\n'
            for i in range(13))
        parsed = comparison.parse_public(output,'sieve',100000,True)
        self.assertEqual(parsed['preparation_ns'],[10])
        self.assertEqual(len(parsed['samples']),13)
        self.assertEqual(len(parsed['caches']),13)
        for altered in (output.replace('PREPARED_PROGRAM','GAS_PLAN'),
                        output.replace(',3,6,100,200',',101,6,100,200',1),
                        output.replace('PREPARED_CACHE,0,','PREPARED_CACHE,1,',1),
                        '\n'.join(output.splitlines()[1:])):
            # Missing construction or inadmissible occupancy cannot be disguised as a valid reused call.
            with self.subTest(output=altered[:90]), self.assertRaises(ValueError):
                comparison.parse_public(altered,'sieve',100000,True)

    def test_public_doom_constructor_role_and_complete_calls(self):
        """Public host loops retain their own constructor, complete calls and events with exact role identity."""
        calls = ''.join(f'DOOM_SAMPLE,native,tick,{i},100,101\n' for i in range(13))
        for prepared in (False,True):
            mode = 'prepared' if prepared else 'planned'
            output = f'API_PREPARE,{mode},10\n'+calls+'DOOM_OK,native,tick,1024005\n'
            parsed = comparison.parse_public(output,'tick',None,prepared,True,1024005)
            self.assertEqual(parsed['preparation_ns'],[10])
            self.assertEqual(len(parsed['samples']),13)
            for altered in (output.replace(',10\n',',0\n',1),
                            output.replace(mode,'foreign',1),output+'unexpected\n',
                            output.replace('DOOM_SAMPLE,native,tick,0,100,101\n','')):
                # Neither core phase output nor a partial host run can stand in for a public API observation.
                with self.subTest(output=altered[:90]), self.assertRaises(ValueError):
                    comparison.parse_public(altered,'tick',None,prepared,True,1024005)

    def test_master_doom_uses_public_constructor_without_source_injection(self):
        """Integrated master uses its existing constructor record, including strict malformed-output refusal."""
        output = 'API_PREPARE,planned,10\n'+''.join(
            f'DOOM_SAMPLE,native,tick,{i},100,101\n' for i in range(13))+'DOOM_OK,native,tick,5\n'
        with tempfile.TemporaryDirectory() as temporary:
            # The host transcript length is fixture-owned even when process execution is mocked.
            folder = Path(temporary)
            (folder/'prepared').mkdir()
            (folder/'prepared/tick.events').write_bytes(b'event')
            trial = comparison.Comparison.__new__(comparison.Comparison)
            trial.identities = {}
            trial.images = {('master','doom'): folder/'driver'}
            trial.report = dict(runs=[])
            trial.save = Mock()
            trial.command = Mock(return_value=(dict(exit_code=0),output))
            with patch.object(comparison,'DOOM',folder), patch.object(comparison,'unchanged'):
                trial.execute('master','tick',1,None,True)
                self.assertEqual(trial.report['runs'][0]['parsed']['preparation_ns'],[10])
                self.assertEqual(trial.command.call_args.args[2]['RAGNAROK_PVM_DOOM_PREPARATION'],'1')
                # An old injected timer or a missing constructor cannot pass on the modern master path.
                for malformed in (output.replace('API_PREPARE,planned,10','MASTER_PREPARE,10'),
                                  output.replace('API_PREPARE,planned,10\n','')):
                    trial.command.return_value = (dict(exit_code=0),malformed)
                    with self.assertRaises(ValueError):
                        trial.execute('master','tick',1,None,True)

    def test_summary_requires_distinct_public_and_core_roles(self):
        """A core-only or duplicated cohort cannot publish an integrated-public-API performance table."""
        runs = []
        for case in [row[0] for row in comparison.CASES]+['init','tick']:
            for order in range(2):
                for role in comparison.ROLES:
                    # Constant inert clocks make only the role/scoping obligations relevant here.
                    samples = [dict(cpu_ns=100,lifecycle_ns=103,attempts=1,nodes=2) for _ in range(13)]
                    parsed=dict(preparation_ns=[10,20],samples=samples)
                    if role=='reference' and case in ('init','tick'):
                        # Reference call-only scores cannot stand in for an invocation lifecycle comparison.
                        parsed['lifecycle']=[dict(restore_ns=2,cpu_ns=100,teardown_ns=1,lifecycle_ns=103) for _ in range(13)]
                    runs.append(dict(case=case,order=order,role=role,parsed=parsed))
        report = dict(status='passed',master='master',candidate='candidate',runs=runs)
        rendered = comparison.summary(report)
        self.assertIn('Ours ordinary API',rendered)
        self.assertIn('Ours prepared API',rendered)
        self.assertIn('Retained-frame core is a separate scope',rendered)
        self.assertIn('Reference instance + restore',rendered)
        lifecycle=next(row['parsed']['lifecycle'] for row in runs if row['role']=='reference' and row['case']=='tick')
        dropped=lifecycle.pop()
        with self.assertRaises(ValueError):
            comparison.summary(report)
        lifecycle.append(dropped)
        for incomplete in (runs[1:],runs+[runs[0]],
                           [row for row in runs if row['role']!='public']):
            with self.assertRaises(ValueError):
                comparison.summary(dict(report,runs=incomplete))

    def test_prior_prepared_role_requires_exact_immutable_head(self):
        """Optional paired baselines require a complete distinct role and an immutable full commit identity."""
        self.assertEqual(comparison.comparison_roles(),comparison.ROLES)
        self.assertEqual(set(comparison.comparison_roles('a'*40)),set(comparison.ROLES)|{'baseline'})
        for bad in ('','HEAD','--all','a'*39,'A'*40,'g'*40,True,42):
            with self.subTest(baseline=bad),self.assertRaises(ValueError):
                comparison.comparison_roles(bad)
        runs=[]
        for case in [row[0] for row in comparison.CASES]+['init','tick']:
            for order in range(2):
                for role in comparison.comparison_roles('a'*40):
                    # Every source role retains full call samples; the reference also retains complete lifecycle phases.
                    samples=[dict(cpu_ns=100,lifecycle_ns=103,attempts=1,nodes=2) for _ in range(13)]
                    parsed=dict(samples=samples,preparation_ns=[10,20])
                    if role=='reference' and case in ('init','tick'):
                        parsed['lifecycle']=[dict(restore_ns=2,cpu_ns=100,teardown_ns=1,lifecycle_ns=103) for _ in range(13)]
                    runs.append(dict(case=case,order=order,role=role,parsed=parsed))
        report=dict(status='passed',master='master',candidate='candidate',prepared_baseline='a'*40,runs=runs)
        self.assertIn('Current / prior',comparison.summary(report))
        with self.assertRaises(ValueError):
            comparison.summary(dict(report,runs=[row for row in runs if row['role']!='baseline']))

    def test_optional_baseline_fetch_rejects_non_commit_input(self):
        """The dispatch input never becomes a Git option or executable shell fragment."""
        section=job_section((ROOT/'.github/workflows/ci.yml').read_text(),'pvm-comparison')
        block=section.split("python3 - <<'PYBASE'\n",1)[1].split('          PYBASE',1)[0]
        source=textwrap.dedent(block)
        for value in ('','a'*40,'HEAD','--upload-pack=bad','a'*40+'; command','A'*40):
            with self.subTest(value=value),patch.dict('os.environ',PVM_COMPARE_PREPARED_BASE=value),patch('subprocess.run') as fetch:
                if value and value!='a'*40:
                    # Invalid selectors fail before the only allowed, argument-vector fetch.
                    with self.assertRaises(ValueError):exec(source,{})
                    fetch.assert_not_called()
                else:
                    exec(source,{})
                    if value:fetch.assert_called_once_with(['git','fetch','--no-tags','origin',value],check=True)
                    else:fetch.assert_not_called()

    def test_regular_comparison_job_and_evidence(self):
        """Regular performance monitoring retains the complete comparison and its evidence."""
        text = (ROOT/'.github/workflows/ci.yml').read_text()
        section = job_section(text,'pvm-comparison')
        for group,command,other in (('x86_64','x86','arm64'),('arm64','arm64','x86')):
            # Inspect applicable steps, so a command present only on the wrong native runner cannot satisfy this contract.
            with self.subTest(architecture=group):
                native = family_section(text,'pvm-comparison',group)
                self.assertIn('run: make check-pvm-native',native)
                self.assertIn('run: make bench-pvm-'+command+'-applications',native)
                self.assertNotIn('run: make bench-pvm-'+other+'-applications',native)
                self.assertIn('build/tests/pvm-'+command+'-applications/*.json',native)
                self.assertIn('build/tests/pvm-'+command+'-applications/summary.md',native)
        self.assertIn('git fetch --no-tags origin master:refs/remotes/origin/master',section)
        self.assertIn('if: always()',section)
        for context,wanted in ((event_context(),True),
                (event_context('pull_request','synchronize'),False),
                (event_context('workflow_dispatch',suite='bench-pvm'),True),
                (event_context('workflow_dispatch',suite='perf'),True),
                (event_context('workflow_dispatch',suite='full'),True)):
            # Default monitoring and explicit requests retain the same checked lifecycle matrix.
            self.assertEqual(bool(expression(job_condition(text,'pvm-comparison'),context)),wanted)
