# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect benchmark inputs, exact locked dependencies and truthful three-engine summaries."""
from copy import deepcopy
import hashlib
import json
import tomllib
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
from dependencies import ROOT
from pvm_benchmark_reference import HEADER,fixtures
from pvm_benchmark_report import ACTIVE_ENGINES,DEFERRED_COMPILER,ENGINES,NAMES,parse_output,aggregate,summarize_benchmark


# Small deterministic durations exercise report logic without running any measured engine.
def output(unavailable=False):
    if unavailable:return '\n'.join(f'unavailable\t{row}\tunsupported platform' for row in range(5))
    return '\n'.join(f'sample\t{row}\t{sample}\t{1000+row+sample}\t50' for row in range(5) for sample in range(13))


class PvmBenchmarkTests(unittest.TestCase):
    """Missing, duplicate, failed or substituted observations cannot become valid benchmark rows."""

    def test_independent_frozen_inputs(self):
        """All five complete guests retain independent outcome/gas expectations and exact bytes."""
        data,count=fixtures();self.assertEqual(count,5)
        self.assertEqual(data,(ROOT/'tests/fixtures/pvm-benchmark.bin').read_bytes())
        descriptor=json.loads((ROOT/'tests/fixtures/pvm_benchmark.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),descriptor['files']['pvm-benchmark.bin'])
        cursor=12
        for kind,expected in ((0,30000),(1,1000),(1,1000),(2,1000),(2,1000)):
            row=HEADER.unpack_from(data,cursor)
            self.assertEqual(row[1],kind);self.assertEqual(row[31],expected)
            cursor+=HEADER.size+row[0]
        self.assertEqual(cursor,len(data))

    def test_lock_identity(self):
        """The standalone benchmark crate introduces no transitive version/checksum changes."""
        upstream=tomllib.loads((ROOT/'vendor/polkavm/Cargo.lock').read_text())['package']
        fields=('name','version','source','checksum')
        known={tuple(p.get(k) for k in fields) for p in upstream}
        packages=tomllib.loads((ROOT/'tests/performance/polkavm/Cargo.lock').read_text())['package']
        for package in packages:
            if package['name']!='ragnarok-pvm-benchmark':
                self.assertIn(tuple(package.get(k) for k in fields),known)

    def test_release_profile_matches_upstream(self):
        """The reference baseline uses upstream LTO/codegen settings rather than weaker local defaults."""
        upstream=tomllib.loads((ROOT/'vendor/polkavm/Cargo.toml').read_text())
        benchmark=tomllib.loads((ROOT/'tests/performance/polkavm/Cargo.toml').read_text())
        self.assertEqual(benchmark['profile']['release'],upstream['profile']['release'])

    def test_parser_rejects_incomplete_or_fallback_samples(self):
        """A zero process exit cannot conceal missing samples, duplicate rows or interpreter fallback."""
        good=output();parse_output(good,'ragnarok')
        for bad in ('',good.rsplit('\n',1)[0],good+'\n'+good.splitlines()[0],
                    good+'\nunavailable\t0\tunsupported platform'):
            with self.subTest(bad=bad[-60:]),self.assertRaises(ValueError):parse_output(bad,'polkavm_compiler')
        with self.assertRaises(ValueError):parse_output(output(True),'polkavm_interpreter')
        with self.assertRaises(ValueError):parse_output(good,'fallback')

    def test_compiled_deferral_is_explicit_and_carries_no_timings(self):
        """The maintainer-selected interpreter baseline cannot acquire fabricated compiler observations."""
        one={engine:parse_output(output(),engine) for engine in ACTIVE_ENGINES}
        one['polkavm_compiler']=[dict(samples=[],reason=DEFERRED_COMPILER,deferred=True) for _ in NAMES]
        cases=aggregate([one,deepcopy(one)])
        text=summarize_benchmark(dict(status='checks-passed',cases=cases))
        self.assertEqual(text.count('| Deferred |'),5)
        self.assertIn(DEFERRED_COMPILER,text)
        self.assertTrue(all(row['engines']['polkavm_compiler']['status']=='deferred' for row in cases))
        corrupt=deepcopy(one);corrupt['polkavm_compiler'][0]['samples']=[{'execution_ns':1}]
        with self.assertRaisesRegex(ValueError,'Unmeasured backend supplied timings'):
            aggregate([corrupt,deepcopy(corrupt)])
        corrupt=deepcopy(cases);corrupt[0]['engines']['polkavm_compiler']['samples']=[{'execution_ns':1}]
        with self.assertRaisesRegex(ValueError,'Unmeasured backend supplied timings'):
            summarize_benchmark(dict(status='checks-passed',cases=corrupt))
        corrupt=deepcopy(one);corrupt['polkavm_compiler'][0]['deferred']=False
        with self.assertRaisesRegex(ValueError,'Inconsistent compiler deferral'):
            aggregate([one,corrupt])

    def test_noise_is_flagged_without_dropping_samples(self):
        """A loaded host may pass correctness but cannot yield an apparently stable speed ratio."""
        one={engine:parse_output(output(engine=='polkavm_compiler'),engine) for engine in ENGINES}
        other=deepcopy(one)
        for row in other['ragnarok']:
            for sample in row['samples']:sample['execution_ns']*=5
        cases=aggregate([one,other]);text=summarize_benchmark(dict(status='checks-passed',cases=cases))
        self.assertIn('Noisy:',text)
        self.assertEqual(len(cases[0]['engines']['ragnarok']['samples']),26)
        self.assertTrue(cases[0]['engines']['ragnarok']['quality']['noisy'])

    def test_failed_run_clears_old_downloads(self):
        """A provenance refusal replaces old Markdown success and removes stale raw samples."""
        import pvm_benchmark
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            (folder/'summary.md').write_text('old success')
            (folder/'samples.csv').write_text('old measurements')
            with patch.object(pvm_benchmark,'BUILD',folder), patch.object(
                    pvm_benchmark,'require_submodule',side_effect=RuntimeError('provenance refusal')):
                with self.assertRaisesRegex(RuntimeError,'provenance refusal'):pvm_benchmark.run()
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertFalse((folder/'samples.csv').exists())
            self.assertIn('**Status: failed**',(folder/'summary.md').read_text())
            self.assertNotIn('old success',(folder/'summary.md').read_text())

    def test_table_and_unavailable_backend(self):
        """Twenty measured samples per workload survive aggregation; unavailable compiled cells stay empty."""
        one={engine:parse_output(output(engine=='polkavm_compiler'),engine) for engine in ENGINES}
        cases=aggregate([one,deepcopy(one)])
        report=dict(status='checks-passed',cases=cases)
        text=summarize_benchmark(report)
        self.assertEqual([row['name'] for row in cases],list(NAMES))
        self.assertIn('PolkaVM compiled',text);self.assertEqual(text.count('| Unavailable |'),5)
        self.assertNotIn('0.00 [0.00',text)
        for mutate in (lambda r:r['cases'].pop(),
                       lambda r:r['cases'][0]['engines']['ragnarok']['samples'].pop(),
                       lambda r:r['cases'][0]['engines']['ragnarok'].update(median_ns=1)):
            changed=deepcopy(report);mutate(changed)
            with self.assertRaises(ValueError):summarize_benchmark(changed)
        inconsistent=deepcopy(one)
        inconsistent['polkavm_compiler']=parse_output(output(),'polkavm_compiler')
        with self.assertRaises(ValueError):aggregate([one,inconsistent])


# Tooling/oracle checks are fast and deterministic; measurements remain an explicit Make target.
if __name__=='__main__':
    unittest.main(verbosity=2)
