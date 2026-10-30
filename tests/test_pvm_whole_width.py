# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Inert source-projection guards for the isolated fixed-width callback experiment."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import pvm_whole_width as h
from pvm_whole_width_projection import derive


class WholeWidthTests(unittest.TestCase):
    """Reject accidental memory projection, width mismatches, bridge drift and clock-gate changes."""

    def test_projection_uses_original_checked_apis_and_closed_table(self):
        """Eight callbacks select static production operations; no data pointer or backing source is projected."""
        with tempfile.TemporaryDirectory(prefix='pvm-width-test-',dir=h.ROOT/'build') as tmp:
            folder=Path(tmp);derive(folder)
            source=(folder/'fast_image.nim').read_text()
            for index,width in enumerate((1,2,4,8)):
                self.assertIn(f'load[{width}](writer, MemoryAddress(address))',source)
                self.assertIn(f'store[{width}](writer, MemoryAddress(address), RegisterValue(value))',source)
                self.assertIn(f'context.loadCallbacks[{index}] = checkedLoad{width}',source)
                self.assertIn(f'context.storeCallbacks[{index}] = checkedStore{width}',source)
            self.assertIn('context.loadCallbacks[i] = nil',source)
            self.assertNotIn('nativeEpoch',source);self.assertNotIn('unsafeAddr',source)
            self.assertFalse((folder/'private_machine.nim.inc').exists())
            header=(folder/'pvm_whole_image.h').read_text()
            self.assertIn('sizeof(pvm_whole_invocation) == 224',header)
            self.assertIn('load_callbacks) == 160',header)
            self.assertIn('context->load_callbacks[i] != loads[i]',header)
            baseline=(h.ROOT/'tests/performance/pvm_whole_image.nim').read_text()
            first=source.index('proc emitMemory(');end=source.index('\nproc enter(',first)
            emitted=source[first:end]
            original=baseline[baseline.index('proc emitMemory('):baseline.index('\nproc enter(')]
            for block in ('for i in 0..<3: storeWord(builder.words, uint32(i+9), 31, 120+i*8)',
                          'for i in 0..<3: loadWord(builder.words, uint32(i+9), 31, 120+i*8)',
                          'builder.exits.add(conditional(builder.words, 1))'):
                self.assertIn(block,emitted);self.assertIn(block,original)

    def test_only_reviewed_clock_projection_changes_between_phases(self):
        """The complete generated set remains equal except four explicit clock-only driver transforms."""
        with tempfile.TemporaryDirectory(prefix='pvm-width-test-',dir=h.ROOT/'build') as one, tempfile.TemporaryDirectory(prefix='pvm-width-test-',dir=h.ROOT/'build') as two:
            derive(Path(one));derive(Path(two),clocked=True)
            h.verify_generated_projection(Path(two),Path(one))
            path=Path(two)/'fast_image.nim';path.write_text(path.read_text()+'\n# changed\n')
            with self.assertRaises(ValueError):h.verify_generated_projection(Path(two),Path(one))

    def test_fixed_protocol_and_complete_owned_inputs(self):
        """One104-process cohort holds original image sizes, production sources and both owned records."""
        self.assertEqual(len(h.matrix()),104)
        self.assertEqual(h.EXPECTED['pinky']['fast'],416152)
        self.assertEqual(h.EXPECTED['sieve']['fast'],1697128)
        owned=h.owned_inputs()
        for name in ('tools/pvm_whole_width_projection.py','tools/pvm_whole_width.py',
                     'tests/performance/pvm_whole_width_controls.nim.inc',
                     'spec/pvm-whole-width-experiment.md','spec/pvm-whole-memory-experiment.md'):
            self.assertIn(h.ROOT/name,owned)


if __name__=='__main__':unittest.main()
