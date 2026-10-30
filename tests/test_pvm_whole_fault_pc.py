# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert fault-PC source-boundary, code-footprint and fixed-cohort refusal checks."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_whole_fault_pc as h
from pvm_whole_fault_pc_projection import derive
from pvm_whole_width_projection import derive as derive_width


def output(guest,arm,sites=100):
    """Synthetic parser-only rows never become actual measurement evidence."""
    spec=h.EXPECTED[guest];size=spec['baseline']-(12*sites if arm=='fast' else 0)
    rows=['WHOLE_INPUT_PREPARE,1,2',f"WHOLE_IMAGE,{size},{spec['instructions']},3,4",
          f"WHOLE_BRIDGE_SHAPE,{sites},{size},{spec['baseline']}",'WHOLE_GAS_DISABLED,1']
    if guest=='pinky':rows+=['GUEST,pinky','WHOLE_HOST_SITES,0']
    for i in (0,1):
        rows.extend([f'WHOLE_RESTORE,{i},0,1',f"WHOLE_EXIT,{i},1,0,1,{spec['total'][0]},{spec['total'][1]},7,8",f'WHOLE_PUBLICATION,{i},0,1'])
        if guest=='pinky':rows.append(f'PINKY_FRAME,{i},209440,245760')
    return '\n'.join(rows+['WHOLE_IMAGE_RETIRE,1,1','WHOLE_PASS,'+str(spec['limit'])])+'\n'


class WholeFaultPcTests(unittest.TestCase):
    """Only failure-PC transport changes; same-work and complete-source gates remain strict."""

    def test_variant_reduces_exactly_to_accepted_baseline(self):
        """Undo the eight failure-only assignments and three emitter edits to recover every baseline byte."""
        with tempfile.TemporaryDirectory(prefix='pvm-fault-pc-test-',dir=h.ROOT/'build') as one, tempfile.TemporaryDirectory(prefix='pvm-fault-pc-test-',dir=h.ROOT/'build') as two:
            folder=Path(one);derive(folder);derive_width(Path(two))
            accepted=(folder/'width_image.nim').read_text()
            self.assertEqual(accepted,(Path(two)/'fast_image.nim').read_text())
            self.assertEqual((folder/'pvm_whole_image.h').read_bytes(),(Path(two)/'pvm_whole_image.h').read_bytes())
            source=(folder/'fast_image.nim').read_text()
            self.assertEqual(source.count('    context.pc = faultPc #'),8)
            self.assertEqual(source.count('faultPc: uint64)'),8)
            source=source.replace('faultPc: uint64)','width: uint64)').replace('    context.pc = faultPc # Publish exact source metadata only for the real checked-memory failure.\n','')
            first=source.index('proc emitMemory(');past=source.index('\nproc enter(',first)
            body=source[first:past]
            # Insert at the unchanged first save, exactly where eager metadata was formerly emitted.
            body=body.replace('  for i in 0..<3: storeWord','  setPc(builder.words, uint64(item.address))\n  for i in 0..<3: storeWord',1)
            body=body.replace('emitImmediate(builder.words, 2, uint64(item.address))','emitImmediate(builder.words, 2, uint64(access.width))').replace('emitImmediate(builder.words, 3, uint64(item.address))','emitImmediate(builder.words, 3, uint64(access.width))')
            self.assertEqual(source[:first]+body+source[past:],accepted)

    def test_clock_only_phase_transition_and_complete_owned_set(self):
        """All generated core files stay identical; four drivers differ only by the reviewed clock transform."""
        with tempfile.TemporaryDirectory(prefix='pvm-fault-pc-test-',dir=h.ROOT/'build') as one, tempfile.TemporaryDirectory(prefix='pvm-fault-pc-test-',dir=h.ROOT/'build') as two:
            derive(Path(one));derive(Path(two),clocked=True);h.verify_generated_projection(Path(two),Path(one))
            for name in ('tools/pvm_whole_fault_pc_projection.py','spec/pvm-whole-fault-pc-experiment.md','tests/performance/pvm_whole_fault_pc_controls.nim.inc'):
                self.assertIn(h.ROOT/name,h.owned_inputs())
            p=Path(two)/'width_image.nim';p.write_text(p.read_text()+'\n# changed\n')
            with self.assertRaises(ValueError):h.verify_generated_projection(Path(two),Path(one))

    def test_footprint_and_exact_work_witnesses_refuse_drift(self):
        """Only twelve bytes per actual static memory site may differ; clocks-disabled rows never qualify."""
        for guest in h.GUESTS:
            base=h.parse(output(guest,'baseline'),guest,'baseline');fast=h.parse(output(guest,'fast'),guest,'fast')
            self.assertEqual(base['code_bytes']-fast['code_bytes'],1200)
            self.assertEqual(base['total_memory'],fast['total_memory'])
            raw=output(guest,'fast')
            for bad in (raw.replace('WHOLE_BRIDGE_SHAPE,100,','WHOLE_BRIDGE_SHAPE,101,'),raw.replace('WHOLE_EXIT,0,1,0,1,','WHOLE_EXIT,0,1,1,1,'),'CORRECTNESS_ONLY_CLOCKS_DISABLED,1\n'+raw):
                with self.assertRaises(ValueError):h.parse(bad,guest,'fast')

    def test_summary_requires_one_fixed_matrix_and_same_site_count(self):
        """All104 owners must describe identical source-site counts in both arms, independently of timing."""
        rows=[dict(guest=g,order=o,sample=s,arm=a,discarded=s<3,run=dict(output=output(g,a)),measured=h.parse(output(g,a),g,a)) for g,o,s,a in h.matrix()]
        self.assertEqual(len(h.summarize(rows)),4)
        self.assertIn("cflags=['-I'+str(folder)]",(h.ROOT/'tools/pvm_whole_fault_pc.py').read_text())
        rows[1]['run']['output']=output('pinky','fast',101);rows[1]['measured']=h.parse(rows[1]['run']['output'],'pinky','fast')
        with self.assertRaises(ValueError):h.summarize(rows)


if __name__=='__main__':unittest.main()
