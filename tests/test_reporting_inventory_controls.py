# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Native inventory refusal verdicts require precise pre-installation output, nonzero exit and a successful positive corpus."""
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from reporting_inventory_controls import compare_inventory_controls


class InventoryControlTests(unittest.TestCase):
    """Refuse success, partial installation, wrong failure and absent genuine positive controls."""

    def run_case(self,output,code,positive=True):
        """Exercise strict output/status bookkeeping without a compiler or protocol implementation."""
        expected=['P 00','B bb','[Assertion Failure] inventory/IncompleteNamespaces']
        cases=[dict(name='missing-child',requests=['C test root 00 params 0000','B bb'],expected=expected)]
        def command(arguments,name):
            """A real request file must exist before the selected process verdict is consumed."""
            self.assertEqual(Path(arguments[-1]).read_text(),'C test root 00 params 0000\nB bb\n')
            return dict(output=output,exit_code=code,log=name,elapsed_seconds=1)
        result=dict(passed=positive)
        with tempfile.TemporaryDirectory() as folder:
            compare_inventory_controls(result,command,'driver','fixture',Path(folder)/'requests.txt',cases)
        return result

    def test_precise_nonzero_refusal(self):
        """The complete prefix and intended assertion must match exactly before the result can pass."""
        result=self.run_case('P 00\nB bb\n[Assertion Failure] inventory/IncompleteNamespaces\n',1)
        self.assertTrue(result['passed']);self.assertEqual(result['inventory_refusals'],1)
        self.assertEqual(result['inventory_actual_sha256'],result['inventory_expected_sha256'])

    def test_success_partial_and_other_failures_are_refused(self):
        """A successful process, too-early crash, published posterior or unrelated diagnostic cannot count as refusal."""
        good='P 00\nB bb\n[Assertion Failure] inventory/IncompleteNamespaces\n'
        for output,code in ((good,0),('P 00\n',1),('P 00\nB bb\nO installed\n'+good,1),(good.replace('IncompleteNamespaces','other'),1)):
            with self.subTest(output=output,code=code):
                self.assertFalse(self.run_case(output,code)['passed'])

    def test_failed_positive_corpus_cannot_authorize_negative_verdicts(self):
        """Compilation/execution failure in the actual positive workload is never a passing refusal control."""
        with self.assertRaises(AssertionError):
            self.run_case('',1,positive=False)


if __name__ == '__main__':
    unittest.main()
