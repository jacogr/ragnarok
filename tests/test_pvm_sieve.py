# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Protect real-guest provenance, complete sample framing and failure-safe benchmark artifacts."""
from copy import deepcopy
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch
from dependencies import ROOT
import pvm_sieve_benchmark as benchmark
from pvm_sieve_report import ENGINES,LIMITS,limits_for_guest,parse_output,parse_process_output,summarize


def output(engine='ragnarok',limit=1000):
    """Use deterministic synthetic clock readings only for report protocol tests."""
    return '\n'.join(f'SIEVE,{engine},{limit},{index},{2000+index},{1000+index}' for index in range(13))


def report(guest='sieve'):
    """Construct every required engine/pass/limit identity with explicit plan preparation."""
    return dict(status='checks-passed',guest=guest,passes=[dict(guest=guest,limit=limit,engine=engine,pass_index=p,
        samples=parse_output(output(engine,limit),engine,limit),
        preparation=dict(cpu_ns=1000,wall_ns=2000,code_bytes=16,block_count=1,payload_bytes=128,cycle_limit=1000000) if engine=='ragnarok_planned' else (dict(cpu_ns=100,wall_ns=200,code_bytes=16,payload_bytes=128,cycle_limit=1000000,priced_blocks=1 if limit==1000 else 2) if engine=='ragnarok_memo' else None))
        for limit in limits_for_guest(guest) for engine in ENGINES for p in range(2)])


class SieveBenchmarkTests(unittest.TestCase):
    """Measured reference inputs remain immutable and incomplete evidence cannot become a green report."""

    def test_frozen_provenance(self):
        """All guest members and exact public source/dependency pins validate without guest compilation."""
        provenance=benchmark.verify_fixture(upstream=ROOT/'vendor/polkavm')
        self.assertEqual(provenance['instruction_set'],'JamV1')
        self.assertEqual(provenance['guest_toolchain'],'nightly-2025-05-10')
        self.assertEqual(provenance['artifact_sha256'],
                         '70519567c4eb3eb0c04ff27b819cc25b95beadfe970d714d45a50aba7f2de43d')

    def test_changed_and_missing_fixture_members(self):
        """Every declared member, including attribution and lock metadata, is mandatory."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            shutil.copytree(benchmark.FIXTURE,folder/'pvm-sieve')
            shutil.copy(ROOT/'tests/fixtures/pvm_sieve.fixture.json',folder)
            members=list((folder/'pvm-sieve').iterdir())
            for path in members:
                original=path.read_bytes()
                try:
                    path.write_bytes(original+b'!')
                    with self.subTest(member=path.name),self.assertRaises(ValueError):
                        benchmark.verify_fixture(folder)
                finally:
                    path.write_bytes(original)
            members[0].unlink()
            with self.assertRaises(FileNotFoundError):benchmark.verify_fixture(folder)

    def test_plan_preparation_protocol(self):
        """Only an explicit bounded complete planned process can supply preparation/resource observations."""
        good='GAS_PLAN,1000,2000,16,1,128,1000000\n'+output('ragnarok_planned')
        parsed=parse_process_output(good,'ragnarok_planned',1000)
        self.assertEqual(parsed['preparation']['payload_bytes'],128)
        for bad in (output('ragnarok_planned'),good.replace(',128,',',127,',1),
                    good.replace(',1000000\n',',0\n',1),good.replace(',16,1,',',16,17,',1),
                    good.replace('GAS_PLAN,1000,','GAS_PLAN,9223372036854775808,',1),
                    good.splitlines()[0]+'\n'+good):
            with self.subTest(tail=bad[-50:]),self.assertRaises(ValueError):parse_process_output(bad,'ragnarok_planned',1000)
        with self.assertRaises(ValueError):parse_process_output(good,'ragnarok',1000)
        data=report();data['passes'][2]['preparation']=None
        with self.assertRaises(ValueError):summarize(data)
        data=report();data['passes'][2]['preparation']['block_count']=2
        with self.assertRaises(ValueError):summarize(data)
        data=report()
        for p in data['passes']:
            if p['engine']=='ragnarok_planned':p['preparation']['cpu_ns']=0
        with self.assertRaises(ValueError):summarize(data)

    def test_memo_protocol_and_visible_cold_cost(self):
        """Initialization, every execution and final occupancy are required; learning cannot be hidden in warmups."""
        good='GAS_MEMO,100,200,16,128,1000000\n'+output('ragnarok_memo')+'\nGAS_MEMO_END,1'
        self.assertEqual(parse_process_output(good,'ragnarok_memo',1000)['preparation']['priced_blocks'],1)
        parse_process_output(good.replace('GAS_MEMO,100,','GAS_MEMO,0,'),'ragnarok_memo',1000)
        for bad in (good.rsplit('\n',1)[0],good+'\nGAS_MEMO_END,1',good.replace('GAS_MEMO_END,1','GAS_MEMO_END,0'),
                    good.replace('GAS_MEMO_END,1','GAS_MEMO_END,17'),good.replace(',16,128,',',16,127,')):
            with self.subTest(tail=bad[-50:]),self.assertRaises(ValueError):parse_process_output(bad,'ragnarok_memo',1000)
        with self.assertRaises(ValueError):parse_process_output(good,'ragnarok',1000)
        data=report();self.assertIn('Init + first ms',summarize(data))
        for p in data['passes']:
            if p['engine']=='ragnarok_memo':p['samples'][0]['cpu_ns']=0
        with self.assertRaises(ValueError):summarize(data)

    def test_explicit_workload_sizes_and_interpreted_scope(self):
        """Every requested sieve size must complete; Pinky and loop controls keep distinct bounded domains."""
        self.assertEqual(LIMITS,(1000,10000,100000,10000000))
        self.assertEqual(limits_for_guest('minimal'),(1000,100000))
        self.assertEqual(limits_for_guest('pinky'),(1,))
        self.assertEqual(ENGINES,('ragnarok','ragnarok_planned','ragnarok_memo','polkavm_interpreter'))
        self.assertIn('CPU mean ± SD ms',summarize(report()))
        self.assertIn('PolkaVM interpreted | — |',summarize(report()))
        for guest in ('sieve','minimal','memset','pinky'):
            self.assertIn('| Limit |',summarize(report(guest)))
            for limit in limits_for_guest(guest):
                prefix='' if guest=='sieve' else 'GUEST,'+guest+'\n'
                parse_process_output(prefix+output('polkavm_interpreter',limit),'polkavm_interpreter',limit,guest)
        with self.assertRaises(ValueError):
            parse_process_output('GUEST,pinky\n'+output(limit=1000),'ragnarok',1000,'pinky')
        with self.assertRaises(ValueError):limits_for_guest('unknown')

    def test_complete_protocol(self):
        """Both clocks and every sample survive parsing in original process order."""
        rows=parse_output(output(),'ragnarok',1000)
        self.assertEqual((rows[0]['wall_ns'],rows[-1]['cpu_ns']),(2000,1012))

    def test_malformed_samples(self):
        """Zero exits cannot conceal truncated, duplicate, reordered, foreign or corrupt measurements."""
        good=output();lines=good.splitlines()
        cases=['', '\n'.join(lines[:-1]),good+'\n'+lines[0], '\n'.join(reversed(lines)),
               good.replace('SIEVE,ragnarok','SIEVE,polkavm_interpreter',1),
               good.replace(',2000,1000',',0,1000',1),good.replace(',2000,1000',',2000,-1',1),
               good.replace(',2000,1000',',2000,1.2',1),good+'\nwarning']
        for bad in cases:
            with self.subTest(tail=bad[-50:]),self.assertRaises(ValueError):parse_output(bad,'ragnarok',1000)
        with self.assertRaises(ValueError):parse_output(good,'compiler',1000)

    def test_incomplete_or_duplicate_report(self):
        """Every pass identity is needed exactly once before any ratios can be published."""
        complete=report();self.assertIn('within dispersion guard',summarize(complete))
        for passes in (complete['passes'][:-1],complete['passes']+[complete['passes'][0]],
                       [complete['passes'][0]]*8):
            with self.assertRaises(ValueError):summarize(dict(status='checks-passed',passes=passes))

    def test_noise_is_retained(self):
        """A slow pass is visible and flagged; no sample is discarded to improve the ratio."""
        noisy=deepcopy(report())
        for row in noisy['passes'][0]['samples']:row['cpu_ns']*=3
        before=deepcopy(noisy)
        self.assertIn('noisy; inspect raw samples',summarize(noisy));self.assertEqual(noisy,before)

    def test_warmups_excluded_only_from_summary(self):
        """Warmup outliers remain raw evidence but cannot distort the measured median."""
        data=report();before=summarize(data)
        for item in data['passes']:
            for row in item['samples'][:3]:row['cpu_ns']=10**12
        after=summarize(data)
        self.assertEqual(after.split('Pricing initialization and first execution')[0],before.split('Pricing initialization and first execution')[0])
        self.assertNotEqual(after,before) # Cold sample zero is now an explicit cost observation, not a hidden warmup.
        self.assertEqual(len(data['passes'][0]['samples']),13)

    def test_failed_rerun_retires_stale_success(self):
        """A provisioning/fixture failure clears old downloadable samples and records a failed verdict."""
        with tempfile.TemporaryDirectory() as temporary:
            folder=Path(temporary)
            for name in ('samples.csv','summary.md','results.json'):(folder/name).write_text('stale success')
            with patch.object(benchmark,'BUILD',folder),patch.object(benchmark,'require_submodule',side_effect=ValueError('bad pin')):
                with self.assertRaisesRegex(ValueError,'bad pin'):benchmark.run()
            self.assertFalse((folder/'samples.csv').exists())
            self.assertEqual(json.loads((folder/'results.json').read_text())['status'],'failed')
            self.assertNotIn('| Limit |',(folder/'summary.md').read_text())

    def test_opt_in_make_scope(self):
        """The maintained command provisions normally and stays outside default verification."""
        make=(ROOT/'Makefile').read_text()
        target=make.split('bench-pvm-sieve: setup\n',1)[1].split('\n\n',1)[0]
        self.assertIn('cargo fetch --locked',target);self.assertIn('tools/pvm_sieve_benchmark.py',target)
        self.assertNotIn('bench-pvm-sieve',make.split('check: ',1)[1].splitlines()[0])
