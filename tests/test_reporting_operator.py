# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Portable bundle/process completeness controls reject mutation, stale builds and misleading stdout."""
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from reporting_operator import materialize,compare_jobs


class ReportingOperatorTests(unittest.TestCase):
    """Exercise only orchestration contracts with explicit process doubles, never protocol expected values."""

    def exercise(self,outputs,*,build=0,mutate=False,change_policy=False):
        """Retain two complete jobs and inspect the exact pathname transport, input bytes and policy identity."""
        jobs=[dict(config='config-'+str(i),genesis=bytes([i]),steps=[bytes([i+2])]) for i in range(2)]
        expected=['C None 1 00','C None 1 11'];calls=[]
        with tempfile.TemporaryDirectory(prefix='operator paths ') as temporary:
            folder=Path(temporary)/'population operator bundles';commands,manifest,paths=materialize(folder,jobs,expected)
            policy=folder/'policy.txt'
            def command(arguments,name):
                """The fake may fail or mutate inputs; matching output alone never supplies success."""
                self.assertEqual(arguments[3],'population')
                for field in Path(arguments[1]).read_text().split():self.assertTrue(Path(bytes.fromhex(field).decode()).is_file())
                policy.write_text('policy-'+str(len(calls) if change_policy else 0))
                if mutate:paths[0][0].write_text('mutated')
                output,code=outputs[len(calls)];calls.append(name)
                return dict(output=output,exit_code=code,log=name,elapsed_seconds=1)
            result=dict(build=dict(exit_code=build),passed=False)
            compare_jobs(result,command,'driver',policy,commands,expected,paths)
            return result,calls,manifest

    def test_complete_jobs_and_portable_manifest(self):
        """Absolute paths with spaces differ across runs while exact content manifests and answers stay identical."""
        outputs=[('C None 1 00\n',0),('C None 1 11\n',0)]
        first,calls,manifest=self.exercise(outputs);second,_,other=self.exercise(outputs)
        self.assertTrue(first['passed'] and second['passed']);self.assertEqual(len(calls),2)
        self.assertEqual(manifest,other);self.assertEqual(first['actual_sha256'],first['expected_sha256'])

    def test_nonzero_missing_and_extra_outputs_fail(self):
        """A correct first command cannot hide a failed, missing or extra result in the second."""
        for output,code in (('C None 1 11\n',2),('',0),('C None 1 11\nextra\n',0)):
            with self.subTest(output=output,code=code):
                result,_,_=self.exercise([('C None 1 00\n',0),(output,code)]);self.assertFalse(result['passed'])

    def test_matching_output_cannot_hide_input_mutation(self):
        """Every declared input is hash-checked after each invocation, including already consumed files."""
        result,_,_=self.exercise([('C None 1 00\n',0),('C None 1 11\n',0)],mutate=True)
        self.assertFalse(result['passed']);self.assertFalse(result['runs'][0]['inputs_unchanged'])

    def test_policy_drift_cannot_pass(self):
        """All commands must use the identical explicit typed policy input."""
        result,_,_=self.exercise([('C None 1 00\n',0),('C None 1 11\n',0)],change_policy=True)
        self.assertFalse(result['passed']);self.assertIsNone(result['policy_sha256'])

    def test_failed_build_never_runs_stale_command(self):
        """Build failure remains authoritative even if an older driver binary exists."""
        result,calls,_=self.exercise([],build=1);self.assertFalse(result['passed']);self.assertEqual(calls,[])
