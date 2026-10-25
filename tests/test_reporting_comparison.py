# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Whole-chain comparison refuses partial, extra, missing and nonzero-exit observations."""
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from reporting_comparison import compare_chains,partition


class ReportingComparisonTests(unittest.TestCase):
    """Exercise process/completeness contracts without any production protocol or compiler execution."""

    def run_case(self,outputs,build=0):
        """Use two bounded independent chains and explicit process results, retaining original output hashes."""
        requests=['C first root 00','B aa','N bb credential/InvalidSignature','C second root 11','B cc']
        expected=['P 00','B aa','O 22','N credential/InvalidSignature','P 11','B cc','O 33']
        calls=[]
        def command(arguments,name):
            """Read actual written requests and return a selected process output without synthesizing missing results."""
            self.assertTrue(Path(arguments[-1]).is_file());calls.append(name)
            output,code=outputs[len(calls)-1]
            return dict(output=output,exit_code=code,log=name,elapsed_seconds=1)
        result=dict(build=dict(exit_code=build),passed=False)
        with tempfile.TemporaryDirectory() as folder:
            compare_chains(result,command,'driver','fixture',Path(folder)/'requests.txt',requests,expected,2)
        return result,calls

    def test_complete_success_retains_all_output(self):
        """Each bounded process must pass and concatenation must match the whole expected sequence."""
        result,calls=self.run_case([('P 00\nB aa\nO 22\nN credential/InvalidSignature\n',0),('P 11\nB cc\nO 33\n',0)])
        self.assertTrue(result['passed']);self.assertEqual(len(calls),2)
        self.assertEqual(result['actual_sha256'],result['expected_sha256'])

    def test_partial_extra_and_missing_rows_fail(self):
        """A valid first chain cannot hide any incomplete or extra second-chain observation."""
        first='P 00\nB aa\nO 22\nN credential/InvalidSignature\n'
        for output in ('','P 11\nB cc\n','P 11\nB cc\nO 33\nextra\n'):
            with self.subTest(output=output):
                result,_=self.run_case([(first,0),(output,0)]);self.assertFalse(result['passed'])

    def test_nonzero_exit_cannot_pass_with_matching_bytes(self):
        """Exact stdout is insufficient if its producing process fails."""
        result,_=self.run_case([('P 00\nB aa\nO 22\nN credential/InvalidSignature\n',0),('P 11\nB cc\nO 33\n',2)])
        self.assertFalse(result['passed']);self.assertEqual(result['actual_sha256'],result['expected_sha256'])

    def test_failed_build_never_executes_stale_driver(self):
        """A compiled-artifact failure blocks every child process."""
        result,calls=self.run_case([],1);self.assertFalse(result['passed']);self.assertEqual(calls,[])

    def test_partition_refuses_missing_or_misdeclared_chains(self):
        """Unknown requests, empty chains and missing/extra expected rows fail before native execution."""
        for requests,expected,count in [(['B aa'],['B aa','O bb'],1),(['C a root 00'],['P 00'],1),
            (['C a root 00','B aa'],['P 00','B aa','O bb'],2),(['C a root 00','B aa'],['P 00','B aa'],1),
            (['C a root 00','X aa'],['P 00','O bb'],1)]:
            with self.subTest(requests=requests,count=count):
                with self.assertRaises(AssertionError):partition(requests,expected,count)
