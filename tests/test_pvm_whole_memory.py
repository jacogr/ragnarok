# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert exact-work, immutable-matrix and revocation-projection guards for one private memory experiment."""
from pathlib import Path
import sys
import hashlib
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_whole_memory as h
from pvm_whole_memory_projection import derive


def output(guest,arm):
    """Synthetic parser fixtures test refusal only; they never enter actual performance evidence."""
    spec=h.EXPECTED[guest]
    rows=['WHOLE_INPUT_PREPARE,1,2',f"WHOLE_IMAGE,{spec[arm]},{spec['instructions']},3,4",'WHOLE_GAS_DISABLED,1']
    if guest=='pinky':rows+=['GUEST,pinky','WHOLE_HOST_SITES,0']
    for i in range(2):
        rows += [f'WHOLE_RESTORE,{i},0,1',f"WHOLE_EXIT,{i},1,0,1,{spec['total'][0]},{spec['total'][1]},7,8"]
        if arm=='fast':rows += ['WHOLE_MEMORY_PATH,'+str(i)+','+','.join(map(str,spec['paths']))]
        rows += [f'WHOLE_PUBLICATION,{i},0,1']
        if guest=='pinky':rows += [f'PINKY_FRAME,{i},209440,245760']
    return '\n'.join(rows+['WHOLE_IMAGE_RETIRE,1,1','WHOLE_PASS,'+str(spec['limit'])])+'\n'


class WholeMemoryTests(unittest.TestCase):
    def test_single_fixed_balanced_transfer_matrix(self):
        """Exactly104fresh owners/208calls cover both guests without changing the initial cohorts."""
        matrix=h.matrix();self.assertEqual(len(matrix),104)
        self.assertEqual(matrix[:2],[('pinky',0,0,a) for a in h.ARMS])
        self.assertEqual(matrix[26:28],[('pinky',1,0,a) for a in h.ARMS[::-1]])
        self.assertEqual(matrix[52][0],'sieve')

    def test_native_hits_and_remaining_helpers_are_actual_separate_work(self):
        """A reduced callback count never replaces unchanged complete guest access totals."""
        for guest in h.GUESTS:
            base=h.parse(output(guest,'baseline'),guest,'baseline')
            fast=h.parse(output(guest,'fast'),guest,'fast')
            self.assertEqual(base['total_memory'],fast['total_memory'])
            self.assertEqual([a+b for a,b in zip(fast['native_hits'],fast['helper_calls'])],fast['total_memory'])
            with self.assertRaises(ValueError):h.parse(output(guest,'baseline'),guest,'fast')
            with self.assertRaises(ValueError):h.parse('CORRECTNESS_ONLY_CLOCKS_DISABLED,1\n'+output(guest,'fast'),guest,'fast')

    def test_refuse_altered_frame_terminal_or_native_split(self):
        """No semantic loss, handoff return or fabricated native-hit distribution can qualify a sample."""
        text=output('pinky','fast')
        for bad in (text.replace('245760','245759'),text.replace('WHOLE_EXIT,1,1,0,1,','WHOLE_EXIT,1,1,0,2,'),
                    text.replace('2929099','2929098'),text.replace('10576','10575')):
            with self.assertRaises(ValueError):h.parse(bad,'pinky','fast')

    def test_summary_replays_all_raw_rows_and_fixed_discards(self):
        """Separate guests/orders/calls retain ten processes each; missing or changed raw evidence fails."""
        rows=[dict(guest=g,order=o,sample=s,arm=a,discarded=s<3,run=dict(output=output(g,a)),
                   measured=h.parse(output(g,a),g,a)) for g,o,s,a in h.matrix()]
        summary=h.summarize(rows);self.assertEqual(len(summary),4)
        self.assertEqual(summary[0]['arms']['fast']['calls'][0]['cpu_ns']['samples'],10)
        with self.assertRaises(ValueError):h.summarize(rows[:-1])

    def test_generated_text_matches_the_executed_prototype(self):
        """Promotion must preserve exact emitter/backing/ABI bytes, including Nim indentation inside literals."""
        with tempfile.TemporaryDirectory(prefix='pvm-whole-text-test-',dir=h.ROOT/'build') as temporary:
            folder=Path(temporary);derive(folder)
            native=(folder/'fast_image.nim').read_text()
            first=native.index('proc emitMemory(');past=native.index('\nproc enter(',first)
            self.assertEqual(hashlib.sha256(native[first:past].encode()).hexdigest(),
                '92f9db1a5e317399c8598d0f02229cbefd92cfdd4b81c96b9108c711beb00080')
            self.assertEqual(hashlib.sha256((folder/'private_machine.nim.inc').read_bytes()).hexdigest(),
                '70ff4b7f68f28aa54b3f9708626b6880e7312531daae1f986e1f6923396430f5')
            self.assertEqual(hashlib.sha256((folder/'pvm_whole_image.h').read_bytes()).hexdigest(),
                '88092d62e11d81810e0fd00e820dac900475f7b230dd862549d4fd76f406770b')
            section=native[native.index('    writer*: nil pointer'):native.index('  LoadCallback')]
            self.assertTrue(all(not line.strip() or line.startswith('    ') and not line.startswith('     ')
                                for line in section.splitlines()))

    def test_projection_revokes_both_writer_stores_and_every_snapshot(self):
        """Source-only generation keeps backing private, includes live alias probes, and defaults clocks off."""
        with tempfile.TemporaryDirectory(prefix='pvm-whole-memory-test-',dir=h.ROOT/'build') as temporary:
            folder=Path(temporary);paths=derive(folder)
            machine=(folder/'private_machine.nim.inc').read_text();native=(folder/'fast_image.nim').read_text()
            self.assertEqual(machine.count('  revokeNativeWindows(writer)'),3)
            self.assertIn('writer.nativeEpoch != high(uint64)',machine)
            self.assertIn('context.testProbe = probe',native)
            self.assertIn('Current shared alias/snapshot revocation generation',native)
            self.assertIn('slot >= writer.pages.len or slot >= writer.dirty.len',native)
            self.assertIn('CORRECTNESS_ONLY_CLOCKS_DISABLED,1',paths['fast']['pinky'].read_text())
            self.assertIn('LEASE_MISSING_PAGE',paths['controls'].read_text())
            derive(folder,clocked=True)
            self.assertNotIn('CORRECTNESS_ONLY_CLOCKS_DISABLED',paths['fast']['pinky'].read_text())


if __name__=='__main__':unittest.main()
