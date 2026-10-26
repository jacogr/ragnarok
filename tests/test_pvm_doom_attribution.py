# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Refuse malformed output/golden records and unintended DOOM CI scheduling."""
import hashlib
from pathlib import Path
import sys
import unittest
import tempfile
from unittest.mock import patch
from copy import deepcopy
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from pvm_doom_attribution import event_hashes,tga_rgba,timing_samples,scope_entries,summary_lines,run
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

    def test_doom_runs_with_regular_performance_requests(self):
        """Master/Perf/full include the real guest, while standalone requests remain isolated."""
        from workflow_fixtures import selected_families,family_section
        text=(ROOT/'.github/workflows/ci.yml').read_text()
        for context,wanted in [(event_context(),True),
                (event_context('workflow_dispatch',suite='full'),True),
                (event_context('workflow_dispatch',suite='perf'),True),
                (event_context('workflow_dispatch',suite='bench-doom'),True),
                (event_context('workflow_dispatch',suite='bench-pvm'),False),
                (event_context('pull_request','labeled','ci:perf'),True),
                (event_context('pull_request','synchronize'),False),
                (event_context('pull_request','labeled','ci:perf',state='closed'),False)]:
            families=selected_families(text,'perf',context)
            self.assertEqual(any(f['group']=='bench-doom'for f in families),wanted)
        section=family_section(text,'perf','bench-doom')
        self.assertIn('run: make bench-pvm-doom',section)
        self.assertNotIn('valgrind',section)
        make=(ROOT/'Makefile').read_text().split('bench-pvm-doom: setup\n')[1].split('\n\n')[0]
        self.assertIn('--timings-only --warmup 1320',make)
        self.assertIn('cargo fetch --locked',make)

    def test_cpu_summary_requires_both_phases_and_orders(self):
        """An empty instruction table is valid for CPU-only runs; partial/fabricated ratios are not."""
        report=dict(warmup_ticks=1320,profiles=[],slowdown={})
        for phase in ('init','tick'):
            report['slowdown'][phase]=[dict(order=i,native_cpu_ns=2000000,
                reference_cpu_ns=1000000,native_over_reference=2.0)for i in (0,1)]
        text='\n'.join(summary_lines(report))
        self.assertIn('Ragnarök CPU ms',text)
        self.assertIn('| tick/1 | 2.000 | 1.000 | 2.000× |',text)
        self.assertNotIn('| Instructions |',text)
        with self.assertRaisesRegex(ValueError,'missing DOOM timing summary'):
            summary_lines(dict(mode='timings',warmup_ticks=1320,profiles=[],slowdown={}))
        for mutation in ('phase','order','ratio','duration'):
            bad=deepcopy(report)
            if mutation=='phase':del bad['slowdown']['init']
            elif mutation=='order':bad['slowdown']['tick'].pop()
            elif mutation=='ratio':bad['slowdown']['tick'][0]['native_over_reference']=1
            else:bad['slowdown']['tick'][0]['reference_cpu_ns']=0
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):summary_lines(bad)

    def test_measurement_modes_refuse_ambiguity_and_wrong_hosts(self):
        """CPU-only mode neither relaxes CI/Linux admission nor combines contradictory modes."""
        with self.assertRaises(ValueError):run(check_only=True,timings_only=True)
        with self.assertRaises(ValueError):run(counts_only=True,timings_only=True)
        with patch('pvm_doom_attribution.platform.system',return_value='Darwin'):
            with self.assertRaisesRegex(RuntimeError,'Linux'):run(timings_only=True)
        with patch('pvm_doom_attribution.platform.system',return_value='Linux'),\
             patch('pvm_doom_attribution.platform.machine',return_value='x86_64'),\
             patch.dict('os.environ',{'GITHUB_ACTIONS':'false'}):
            with self.assertRaisesRegex(RuntimeError,'timings require CI'):run(timings_only=True)

    def test_cpu_only_executes_complete_checks_without_profiler(self):
        """Drive the real orchestration with inert tools: eight timing processes and six refusals, no Valgrind."""
        import json
        import contextlib
        import pvm_doom_attribution as doom
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);build=root/'build';crate=root/'crate';upstream=root/'upstream'
            for path in (build,crate/'src',upstream/'crates',root/'src/pvm',root/'spec'):
                path.mkdir(parents=True,exist_ok=True)
            files=['src/pvm/machine.nim','src/codec/natural.nim',
                'tests/performance/pvm_doom.nim','tests/performance/pvm_sieve_clock.h',
                'tools/pvm_doom_attribution.py','tools/pvm_instruction_profile.py',
                'tools/native_checks.py','tools/pvm_opcode_census.py','tools/setup_nimony.py',
                'Makefile','spec/toolchain.json']
            for name in files:
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('fixture')
            (root/'spec/polkavm-pins.json').write_text(json.dumps(dict(commit='pin')))
            (root/'spec/pvm-doom-assets.json').write_text(json.dumps(dict(polkavm_commit='pin',files={})))
            (root/'spec/bandersnatch-pins.json').write_text(json.dumps(dict(rust='pinned')))
            (upstream/'Cargo.lock').write_text('package = []\n')
            (crate/'Cargo.lock').write_text('[[package]]\nname = "ragnarok-pvm-doom"\n')
            (crate/'Cargo.toml').write_text('fixture');(crate/'src/main.rs').write_text('fixture')
            target=root/'target';reference=target/'release/ragnarok-pvm-doom'
            reference.parent.mkdir(parents=True);reference.write_bytes(b'reference')
            native=build/'guest';native.write_bytes(b'native');(build/'doom.polkavm').write_bytes(b'blob')
            (build/'golden.tga').write_bytes(b'golden')
            frame=bytes(1024000);event=b'\1'+len(frame).to_bytes(4,'little')+frame
            prepared=build/'prepared';prepared.mkdir()
            for phase in ('init','tick'):
                (prepared/(phase+'.input')).write_bytes(b'input')
                (prepared/(phase+'.expected')).write_bytes(b'expected-state')
                (prepared/(phase+'.events')).write_bytes(event)
            calls=[]
            mutate_source=[False]
            class Checks:
                def __init__(self,unused):self.folder=build
                def command(self,args,name,**kwargs):
                    # Fixed tools return only their declared records; no command or binary is executed.
                    calls.append((args,name));text='';code=0
                    if name=='head':text='head\n'
                    elif name.endswith(('-assertions','-state','-output')):
                        engine=name.split('-')[0];kind=name.split('-')[1];code=1
                        text={'assertions':'doom '+engine+' assertion control',
                              'state':'doom terminal gas mismatch'if engine=='native'else'DOOM terminal state mismatch',
                              'output':'doom event payload mismatch'if engine=='native'else'DOOM event mismatch'}[kind]
                    elif name.startswith(('native-','reference-','timing-')):
                        if name.startswith('timing-'):
                            _,phase,order,engine=name.split('-')
                            text=''.join(f'DOOM_SAMPLE,{engine},{phase},{i},{100+i},{200+i}\n'for i in range(13))
                        else:
                            engine,phase=name.split('-');phase='tick'if phase=='restored'else phase
                        text+=f'DOOM_OK,{engine},{phase},{len(event)}\n'
                    if mutate_source[0] and name=='timing-tick-1-reference':
                        # A source edit after successful timing must invalidate the final report.
                        (root/'Makefile').write_text('changed after collection')
                    return dict(exit_code=code,output=text,log=name+'.log')
            with contextlib.ExitStack() as patches:
                for name,value in [('ROOT',root),('BUILD',build),('CRATE',crate),('TARGET',target),
                                   ('NativeChecks',Checks)]:
                    patches.enter_context(patch.object(doom,name,value))
                patches.enter_context(patch.object(doom,'require_submodule',return_value=upstream))
                patches.enter_context(patch.object(doom,'installed',return_value=(root/'compiler',None)))
                patches.enter_context(patch.object(doom,'build',return_value=({},native)))
                patches.enter_context(patch.object(doom,'cpu_model',return_value='test'))
                patches.enter_context(patch.object(doom,'tga_rgba',return_value=(640,400,bytes([0,0,0,255])*256000)))
                patches.enter_context(patch.object(doom.platform,'system',return_value='Linux'))
                patches.enter_context(patch.object(doom.platform,'machine',return_value='x86_64'))
                patches.enter_context(patch.dict('os.environ',{'GITHUB_ACTIONS':'true'}))
                for name in ('collect','calibrate_scope','capture_generated_sources'):
                    patches.enter_context(patch.object(doom,name,side_effect=AssertionError('profiler invoked')))
                doom.run(warmup=1320,timings_only=True)
                report=json.loads((build/'results.json').read_text())
                summary=(build/'summary.md').read_text()
                mutate_source[0]=True
                with self.assertRaisesRegex(ValueError,'changed DOOM source'):
                    doom.run(warmup=1320,timings_only=True)
                self.assertEqual(json.loads((build/'results.json').read_text())['status'],'failed')
                self.assertFalse((build/'summary.md').exists())
            self.assertEqual(report['status'],'checks-passed')
            self.assertEqual(len(report['controls']),6)
            self.assertEqual(len(report['timing_runs']),8)
            self.assertEqual(report['profiles'],[])
            self.assertTrue(all(len(row['samples'])==13 for row in report['timing_runs']))
            self.assertFalse(any('valgrind'in str(args[0])for args,name in calls))
            self.assertIn('| init/0 |',summary)
            self.assertEqual((prepared/'tick.expected').read_bytes(),b'expected-state')
            self.assertEqual((prepared/'tick.events').read_bytes(),event)
