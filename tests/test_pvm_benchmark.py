# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect benchmark inputs, exact locked dependencies and truthful interpreter and cold-cost summaries."""
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
from pvm_gas_reference import simulate,tables
from pvm_benchmark_report import ACTIVE_ENGINES,DEFERRED_COMPILER,ENGINES,NAMES,parse_output,aggregate,summarize_benchmark


# Small deterministic durations exercise report logic without running any measured engine.
def output(unavailable=False,planned=False,memo=False):
    """Synthetic samples preserve complete rows and explicit prepared-policy witnesses."""
    if unavailable:return '\n'.join(f'unavailable\t{row}\tunsupported platform' for row in range(len(NAMES)))
    lines=[]
    for row in range(len(NAMES)):
        if planned:lines.append(f'gas-plan\t{row}\t50\t16\t1\t128\t1000000')
        if memo:lines.append(f'gas-memo\t{row}\t50\t16\t128\t1000000')
        lines.extend(f'sample\t{row}\t{sample}\t{1000+row+sample}\t50' for sample in range(13))
        if memo:lines.append(f'gas-memo-end\t{row}\t1')
    return '\n'.join(lines)


class PvmBenchmarkTests(unittest.TestCase):
    """Missing, duplicate, failed or substituted observations cannot become valid benchmark rows."""

    def test_independent_frozen_inputs(self):
        """Every complete guest retains independent outcome/gas expectations and exact bytes."""
        data,count=fixtures();self.assertEqual(count,len(NAMES))
        self.assertEqual(data,(ROOT/'tests/fixtures/pvm-benchmark.bin').read_bytes())
        descriptor=json.loads((ROOT/'tests/fixtures/pvm_benchmark.fixture.json').read_text())
        self.assertEqual(hashlib.sha256(data).hexdigest(),descriptor['files']['pvm-benchmark.bin'])
        cursor=12
        original_end=12;ten_end=12
        for index,(kind,expected) in enumerate(((0,30000),(1,1000),(1,1000),(2,1000),(2,1000),
                                               (0,3),(0,48),(3,None),(4,1000),(4,1000),(5,1000))):
            row=HEADER.unpack_from(data,cursor)
            self.assertEqual(row[1],kind)
            if expected is not None:self.assertEqual(row[31],expected)
            cursor+=HEADER.size+row[0]
            if index==4:original_end=cursor
            if index==9:ten_end=cursor
        self.assertEqual(cursor,len(data))
        # Historical five-row bytes are frozen independently of the expanded corpus descriptor.
        historical=data[:8]+(5).to_bytes(4,'little')+data[12:original_end]
        self.assertEqual(hashlib.sha256(historical).hexdigest(),
                         'c6e7edfe2ffc0eb83a4c7fedfecd0ce7a6cd7844abb35d43916b3a8d319a154e')
        ten=data[:8]+(10).to_bytes(4,'little')+data[12:ten_end]
        self.assertEqual(hashlib.sha256(ten).hexdigest(),
                         '09b42cdc62759e569389e3f799c97adc478aae415c023aca02b5a96550e14801')

    def test_new_dimensions_and_bit_expectations(self):
        """Short calls and sparse sets stay distinct; bit results have an independent literal final witness."""
        data,count=fixtures();cursor=12;rows=[]
        for _ in range(count):
            row=HEADER.unpack_from(data,cursor);rows.append(row);cursor+=HEADER.size+row[0]
        self.assertEqual([row[2] for row in rows[5:10]], [1,16,1000,1000,1000])
        self.assertEqual([row[3] for row in rows[8:10]], [0x10000,0x10fff])
        control=rows[10]
        self.assertEqual((control[1],control[3],control[8]),(5,8,21))
        self.assertEqual((control[6],control[4],control[9],control[7]),(15,22,22,25))
        self.assertEqual(control[31],1000);self.assertEqual(control[34],1000)
        bits=rows[7]
        self.assertEqual(bits[1],3)
        self.assertEqual(bits[25:32],(9,0,8,281474976710911,578703756024086528,13,18374967954648334848))
        self.assertEqual(bits[34],1000)
        # Row dropping or relabeling cannot retain a green strict parser result.
        complete=output();without_new='\n'.join(line for line in complete.splitlines()
                                               if int(line.split('\t')[1])<5)
        with self.assertRaises(ValueError):parse_output(without_new,'ragnarok')

    def test_nonzero_block_prices_keep_original_code_positions(self):
        """A branch to an earlier noncheap opcode must not become a wrapped absent/cheap byte when pricing the second block."""
        first=[bytes((131,119,1)),bytes((40,5,0,0,0))]
        second=[bytes((131,170,1)),bytes((83,74,5,0,0,0,245,255,255,255)),bytes((50,2))]
        definitions=tables()
        self.assertEqual(simulate(second,definitions,prefix=first),(22,25))
        self.assertNotEqual(simulate(second,definitions),(22,25))

    def test_lock_identity(self):
        """The standalone benchmark crate introduces no transitive version/checksum changes."""
        upstream=tomllib.loads((ROOT/'vendor/polkavm/Cargo.lock').read_text())['package']
        fields=('name','version','source','checksum')
        known={tuple(p.get(k) for k in fields) for p in upstream}
        packages=tomllib.loads((ROOT/'tests/performance/polkavm/Cargo.lock').read_text())['package']
        for package in packages:
            if package['name']!='ragnarok-pvm-benchmark':
                self.assertIn(tuple(package.get(k) for k in fields),known)

    def test_planned_mode_requires_complete_policy_witnesses(self):
        """A dynamic run cannot be relabeled; metadata and repeated one-time setup observations must agree."""
        good=output(planned=True);parse_output(good,'ragnarok_planned')
        for bad in (output(),good.replace('gas-plan\t0\t50','gas-plan\t0\t51',1),
                    good.replace('\t16\t1\t128\t1000000','\t16\t1\t127\t1000000',1),
                    good.replace('\t16\t1\t128\t1000000','\t16\t1\t128\t0',1),
                    good+'\n'+good.splitlines()[0]):
            with self.subTest(tail=bad[-60:]),self.assertRaises(ValueError):parse_output(bad,'ragnarok_planned')
        with self.assertRaises(ValueError):parse_output(good,'ragnarok')

    def test_memo_requires_initialization_and_complete_occupancy(self):
        """A warmed memo cannot be relabeled, truncated or supplied with unverified cold metadata."""
        good=output(memo=True);parse_output(good,'ragnarok_memo')
        for bad in (output(),good.replace('gas-memo-end\t0\t1','gas-memo-end\t0\t0',1),
                    good.replace('gas-memo\t0\t50','gas-memo\t0\t51',1),
                    good.replace('gas-memo-end\t0\t1','gas-memo-end\t0\t17',1),
                    good.replace('gas-memo-end\t0\t1\n','',1),good+'\n'+good.splitlines()[-1]):
            with self.subTest(tail=bad[-50:]),self.assertRaises(ValueError):parse_output(bad,'ragnarok_memo')
        with self.assertRaises(ValueError):parse_output(good,'ragnarok')
        one={e:parse_output(output(e=='polkavm_compiler',e=='ragnarok_planned',e=='ragnarok_memo'),e) for e in ENGINES}
        cases=aggregate([one,deepcopy(one)])
        broken=deepcopy(cases);broken[0]['engines']['ragnarok_memo']['samples'][0]['execution_ns']=0
        with self.assertRaises(ValueError):summarize_benchmark(dict(status='checks-passed',cases=broken))

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
        one={engine:parse_output(output(planned=engine=='ragnarok_planned',memo=engine=='ragnarok_memo'),engine) for engine in ACTIVE_ENGINES}
        one['polkavm_compiler']=[dict(samples=[],reason=DEFERRED_COMPILER,deferred=True) for _ in NAMES]
        cases=aggregate([one,deepcopy(one)])
        text=summarize_benchmark(dict(status='checks-passed',cases=cases))
        self.assertEqual(text.count('| Deferred |'),len(NAMES))
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
        one={engine:parse_output(output(engine=='polkavm_compiler',engine=='ragnarok_planned',engine=='ragnarok_memo'),engine) for engine in ENGINES}
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
        one={engine:parse_output(output(engine=='polkavm_compiler',engine=='ragnarok_planned',engine=='ragnarok_memo'),engine) for engine in ENGINES}
        cases=aggregate([one,deepcopy(one)])
        report=dict(status='checks-passed',cases=cases)
        text=summarize_benchmark(report)
        self.assertEqual([row['name'] for row in cases],list(NAMES))
        self.assertIn('PolkaVM compiled',text);self.assertEqual(text.count('| Unavailable |'),len(NAMES))
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
