# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert proof that one bounded helper cache retains the compact compiler and strict source/work gates."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_whole_read_cache as h
from pvm_whole_read_cache_projection import derive
from pvm_whole_fault_pc_projection import derive as derive_compact
import test_pvm_whole_memory as shared_guards


def output(guest,arm,hits=100):
    """Synthetic refusal fixtures never enter native performance evidence."""
    spec=h.EXPECTED[guest];sites=3860 if guest=='pinky' else 17871
    rows=['WHOLE_INPUT_PREPARE,1,2',f"WHOLE_IMAGE,{spec[arm]},{spec['instructions']},3,4",
          f"WHOLE_BRIDGE_SHAPE,{sites},{spec[arm]},{spec['original_width']}",'WHOLE_GAS_DISABLED,1']
    if guest=='pinky':rows+=['GUEST,pinky','WHOLE_HOST_SITES,0']
    for i in (0,1):
        rows+=[f'WHOLE_RESTORE,{i},0,1',f"WHOLE_EXIT,{i},1,0,1,{spec['total'][0]},{spec['total'][1]},7,8"]
        if arm=='fast':rows.append(f'WHOLE_READ_CACHE,{i},{hits},200,3')
        rows.append(f'WHOLE_PUBLICATION,{i},0,1')
        if guest=='pinky':rows.append(f'PINKY_FRAME,{i},209440,245760')
    return '\n'.join(rows+['WHOLE_IMAGE_RETIRE,1,1','WHOLE_PASS,'+str(spec['limit'])])+'\n'


class WholeReadCacheTests(unittest.TestCase):
    """Retain typed owners only, behind original fast paths and checks; reject evidence drift."""

    def test_compact_compiler_and_abi_are_byte_identical(self):
        """Only the machine import changes; native instructions, bridge, callback table and ABI stay exact."""
        with tempfile.TemporaryDirectory(prefix='pvm-read-cache-test-',dir=h.ROOT/'build') as one, tempfile.TemporaryDirectory(prefix='pvm-read-cache-test-',dir=h.ROOT/'build') as two:
            folder=Path(one);derive(folder);derive_compact(Path(two))
            accepted=(Path(two)/'fast_image.nim').read_text()
            self.assertEqual((folder/'compact_image.nim').read_text().replace('import ../../src/pvm/program\ninclude "./baseline_machine.nim.inc"','import ../../src/pvm/[program, machine]'),accepted)
            self.assertEqual((folder/'baseline_machine.nim.inc').read_text().replace('import ../../src/pvm/program','import ./program'),(h.ROOT/'src/pvm/machine.nim').read_text())
            self.assertEqual((folder/'fast_image.nim').read_text().replace('import ../../src/pvm/program\ninclude "./private_machine.nim.inc"','import ../../src/pvm/[program, machine]'),accepted)
            self.assertEqual((folder/'pvm_whole_image.h').read_bytes(),(Path(two)/'pvm_whole_image.h').read_bytes())

    def test_checked_cache_admission_and_shared_alias_retirement(self):
        """Cache fields/updates stay private; original load checks precede backup lookup and COW precedes mutation."""
        with tempfile.TemporaryDirectory(prefix='pvm-read-cache-test-',dir=h.ROOT/'build') as temporary:
            folder=Path(temporary);derive(folder);source=(folder/'private_machine.nim.inc').read_text()
            self.assertIn('readCache: array[64, nil PageData]',source)
            first=source.index('proc loadScalar[');load=source[first:source.index('\nproc load*',first)]
            self.assertLess(load.index('start >= 0x10000'),load.index('let cached'))
            self.assertLess(load.index('let readable'),load.index('let cached'))
            self.assertIn('cached != nil and uint64(uint32(cached.index)) == tag',load)
            self.assertIn('writer.readPage = cached',load)
            clone=source[source.index('proc cloneWriterChunk'):source.index('\nproc prepareWriterSpan')]
            self.assertLess(clone.index('writer.readCache[bucket] = nil'),clone.index('writer.pages[slot] = pageWithAccess'))
            snapshot=source[source.index('proc snapshotMemory*'):source.index('\nproc captureMachine*')]
            self.assertLess(snapshot.index('writer.readCache[bucket] = nil'),snapshot.index('let frozen ='))
            for token in ('nativeEpoch','clearWindows','chunkPointer'):self.assertNotIn(token,source)
            self.assertNotIn('readCache*',source)

    def test_clock_only_projection_and_same_head_input_guards(self):
        """The reviewed source transition and dirty/new-owned/dependency/archive refusal are unchanged."""
        with tempfile.TemporaryDirectory(prefix='pvm-read-cache-test-',dir=h.ROOT/'build') as one, tempfile.TemporaryDirectory(prefix='pvm-read-cache-test-',dir=h.ROOT/'build') as two:
            derive(Path(one));derive(Path(two),clocked=True);h.verify_generated_projection(Path(two),Path(one))
        with mock.patch.object(shared_guards,'h',h):
            shared_guards.WholeMemoryTests().test_same_head_dirty_template_refuses_before_build()
        for name in ('tools/pvm_whole_read_cache_projection.py','spec/pvm-whole-read-cache-experiment.md','tests/performance/pvm_whole_read_cache_controls.nim.inc'):
            self.assertIn(h.ROOT/name,h.owned_inputs())

    def test_native_shape_work_and_helper_counts_remain_separate(self):
        """Cache hits do not replace callbacks or native work; every process must keep identical actual counts."""
        for guest in h.GUESTS:
            base=h.parse(output(guest,'baseline'),guest,'baseline');fast=h.parse(output(guest,'fast'),guest,'fast')
            self.assertEqual(base['code_bytes'],fast['code_bytes'])
            self.assertEqual(base['helper_calls'],fast['helper_calls']);self.assertEqual(fast['native_hits'],[0,0])
            self.assertEqual(fast['read_cache'],[100,200,3]);self.assertIsNone(base['read_cache'])
            with self.assertRaises(ValueError):h.parse(output(guest,'fast').replace('WHOLE_READ_CACHE,1,100,','WHOLE_READ_CACHE,1,101,'),guest,'fast')
            with self.assertRaises(ValueError):h.parse('CORRECTNESS_ONLY_CLOCKS_DISABLED,1\n'+output(guest,'fast'),guest,'fast')
        rows=[dict(guest=g,order=o,sample=s,arm=a,discarded=s<3,run=dict(output=output(g,a)),measured=h.parse(output(g,a),g,a)) for g,o,s,a in h.matrix()]
        self.assertEqual(len(h.summarize(rows)),4)
        rows[1]['run']['output']=output('pinky','fast',101);rows[1]['measured']=h.parse(rows[1]['run']['output'],'pinky','fast')
        with self.assertRaises(ValueError):h.summarize(rows)


if __name__=='__main__':unittest.main()
