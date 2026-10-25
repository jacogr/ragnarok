# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Refuse malformed output/golden records and unintended DOOM CI scheduling."""
import hashlib
from pathlib import Path
import sys
import unittest
import tempfile
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from pvm_doom_attribution import event_hashes,tga_rgba,timing_samples,scope_entries
from pvm_instruction_profile import collect
from workflow_fixtures import event_context,expression,job_condition,job_section


class DoomAttributionTests(unittest.TestCase):
    def test_complete_event_stream_and_tampering(self):
        """Hash all ordered host bytes and report each full video image separately."""
        frame=bytes([7])*1024000
        data=b'\1'+len(frame).to_bytes(4,'little')+frame+b'\4\1\0\0\0x'
        result=event_hashes(data)
        self.assertEqual(result['frames'],[hashlib.sha256(frame).hexdigest()])
        self.assertEqual(result['event_counts'],{0:0,1:1,4:1})
        self.assertNotEqual(event_hashes(data[:-1]+b'y')['sha256'],result['sha256'])
        for bad in (data[:-1],data+b'\0',b'\2\0\0\0\0',b'\1\1\0\0\0x',b''):
            # No partial output or foreign kind may provide a successful correctness hash.
            with self.subTest(size=len(bad)),self.assertRaises(ValueError):event_hashes(bad)

    def tga(self,kind=2,origin=32):
        """Two independent colored pixels make origin and RLE mistakes visible."""
        header=bytearray(18);header[2]=kind;header[12]=2;header[14]=1;header[16]=24;header[17]=origin
        return bytes(header)

    def test_tga_origins_and_rle(self):
        """Normalize BGR and both packet forms without accepting excess/truncated pixels."""
        raw=b'\1\2\3\4\5\6';wanted=bytes([3,2,1,255,6,5,4,255])
        self.assertEqual(tga_rgba(self.tga()+raw),(2,1,wanted))
        self.assertEqual(tga_rgba(self.tga(origin=48)+raw)[2],wanted[4:]+wanted[:4])
        self.assertEqual(tga_rgba(self.tga(kind=10)+b'\1'+raw)[2],wanted)
        self.assertEqual(tga_rgba(self.tga(kind=10)+b'\x81'+raw[:3])[2],wanted[:4]*2)
        for bad in (b'',self.tga()+raw[:-1],self.tga(kind=10)+b'\x82'+raw[:3]):
            with self.subTest(size=len(bad)),self.assertRaises(ValueError):tga_rgba(bad)

    def test_timing_framing_and_scope(self):
        """Reject reordered, partial, unvalidated and zero-duration timing processes."""
        rows=[f'DOOM_SAMPLE,native,tick,{i},{100+i},{200+i}' for i in range(13)]
        complete='\n'.join(rows+['DOOM_OK,native,tick,1024005'])+'\n'
        self.assertEqual(len(timing_samples(complete,'native','tick',1024005)),13)
        for bad in (complete.replace(',0,100,',',1,100,'),complete.replace(',100,200',',0,200'),complete.replace('DOOM_OK,native','DOOM_OK,reference'),complete+'extra\n'):
            with self.subTest(output=bad[:40]),self.assertRaises(ValueError):
                timing_samples(bad,'native','tick',1024005)
        raw='cfn=runDoom_0_guest\ncalls=1 0\ncfn=outside\ncalls=50 0\n'
        self.assertEqual(scope_entries(raw,'native'),1)
        self.assertEqual(scope_entries(raw,'reference'),0)
        reference='cfn=_RNvMCsample_17ragnarok_pvm_doomNtB2_5Guest3run\ncalls=1 0\ncfn=ragnarok_pvm_doom::Guest::run::{closure}\ncalls=8 0\n'
        self.assertEqual(scope_entries(reference,'reference'),1)

    def test_deep_collection_preserves_diagnostic_options(self):
        """Source/cache attribution requests do not alter ordinary collection defaults."""
        with tempfile.TemporaryDirectory() as folder:
            class Checks:
                def __init__(self):self.folder=Path(folder);self.arguments=None
                def command(self,args,*unused,**kwargs):
                    self.arguments=args;(self.folder/'sample.callgrind').write_text('raw');return {}
            checks=Checks()
            collect(checks,'guest','sample','runDoom_*',{},30,instructions=True,deep=True)
            for option in ('--cache-sim=yes','--read-inline-info=yes','--compress-pos=no','--demangle=no'):
                self.assertIn(option,checks.arguments)
            collect(checks,'guest','sample','runDoom_*',{},30)
            self.assertIn('--cache-sim=no',checks.arguments)
            self.assertNotIn('--read-inline-info=yes',checks.arguments)

    def test_doom_is_explicit_and_isolated(self):
        """Ordinary master/full/unit work never launches the expensive real guest profile."""
        text=(ROOT/'.github/workflows/ci.yml').read_text();condition=job_condition(text,'profile-doom')
        for context,wanted in [(event_context(),False),(event_context('workflow_dispatch',suite='profile-doom'),True),(event_context('workflow_dispatch',suite='profile-pvm'),False),(event_context('workflow_dispatch',suite='full'),False),(event_context('pull_request','labeled','ci:perf'),False)]:
            self.assertEqual(bool(expression(condition,context)),wanted)
        section=job_section(text,'profile-doom')
        self.assertIn('run: make profile-pvm-doom',section)
        self.assertIn("PVM_DOOM_COUNTS_ONLY: ${{ inputs.pvm_doom_counts_only && '1' || '0' }}",section)
        self.assertIn('--counts-only', (ROOT/'Makefile').read_text())
        self.assertIn('valgrind=1:3.22.0-0ubuntu3',section)
        self.assertIn('build/tests/pvm-doom/reference-source/**/*.rs',section)
        self.assertNotIn('continue-on-error',section)
