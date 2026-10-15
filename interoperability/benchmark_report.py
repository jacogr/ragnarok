#!/usr/bin/env python3
"""Same-host checked complete-report stages and two-credential workflow; Nim uses LTO exclusively."""
import argparse
import hashlib
import json
import math
import os
import platform
import random
import re
import statistics
import subprocess
import sys
import time
from pathlib import Path
from report_oracle import ROOT
from report_fixtures import fixtures
from test_work_report import BUILD, commands, prepare_observers
from mojo_support import compiler

LANGUAGES = ('nim','odin','mojo')
MODES = ('decode','encode','owned','hash','verify2','pipeline')
RAW = BUILD/'raw'


# Hash only project-owned language/adapter/spec inputs; dependency revisions remain identified by their pins.
def source_hashes():
    paths = [path for base in ('nim','odin','mojo') for path in (ROOT/base).rglob('*')
             if path.suffix in ('.nim','.odin','.mojo')]
    paths += [Path(__file__), ROOT/'interoperability/report_oracle.py', ROOT/'interoperability/report_fixtures.py',
              ROOT/'interoperability/test_work_report.py', ROOT/'interoperability/bench/observe.c',
              ROOT/'interoperability/mojo/os.c',ROOT/'spec/work-report.md',ROOT/'spec/pins.json',
              ROOT/'spec/crypto-pins.json',ROOT/'spec/mojo-pins.json']
    return {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


# Build normal and allocation-only binaries; prospective runs wrap each direct compiler command themselves.
def build():
    BUILD.mkdir(parents=True,exist_ok=True)
    helpers = prepare_observers()
    result = {}
    for language in LANGUAGES:
        result[language] = []
        for instrumented in (False,True):
            command = list(map(str,commands(language,instrumented)[0]))
            with (BUILD/f'{language}-report-build-{int(instrumented)}.log').open('w') as log:
                subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
            result[language].append(command)
    return helpers,result


# Empirical percentiles are labelled separately for batches and true individual-operation samples.
def distribution(values):
    ordered = sorted(values)
    assert ordered and all(value > 0 for value in ordered)
    return dict(median=statistics.median(values),p95=ordered[math.ceil(.95*len(ordered))-1],
                p99=ordered[math.ceil(.99*len(ordered))-1],min=min(values),max=max(values))


# Reject missing preflight, changed bytes/messages, fake checksums and mixed instrumentation/timing output.
def parse(output, value, iterations, samples, latency, instrumented, language):
    lines = [line.split() for line in output.splitlines()]
    expected = ['VERIFY',value['wire'].hex(),value['message'].hex(),'1']
    assert lines and lines[0] == expected, ('independent full-byte/message/credential preflight failed',output[:300])
    assert all(parts and parts[0] in ('VERIFY','BATCH','LATENCY','END','ALLOC','ALLOC_NIM','ALLOC_MOJO_HEAP') for parts in lines)
    assert sum(parts[0] == 'VERIFY' for parts in lines) == 1
    ending = [parts for parts in lines if parts[0] == 'END']
    assert len(ending) == 1 and lines[-1] == ending[0] and len(ending[0]) == 3
    calls = min(iterations,64) + (iterations if instrumented else samples*iterations+latency)
    assert int(ending[0][1]) == (len(value['wire']) if calls%2 else 0), 'operation checksum mismatch'
    assert int(ending[0][2]) > 0, 'missing process RSS observation'
    batches = [parts for parts in lines if parts[0] == 'BATCH']
    latencies = [parts for parts in lines if parts[0] == 'LATENCY']
    allocations = [parts for parts in lines if parts[0].startswith('ALLOC')]
    if instrumented:
        # Instrumentation binaries cannot be silently used as throughput measurements.
        assert not batches and not latencies and len(allocations) == 1
        parts = allocations[0]
        assert int(parts[1]) == iterations
        if language == 'mojo':
            assert parts[0] == 'ALLOC_MOJO_HEAP' and len(parts) == 3
            return dict(calls_per_operation=None,frees_per_operation=None,live_delta_bytes=int(parts[2]),
                        requested_bytes_per_operation=None,scope='public process malloc; SDK/native providers included; allocation calls unavailable')
        if language == 'nim':
            assert parts[0] == 'ALLOC_NIM'
            counts = re.search(r'allocCount:\s*(\d+).*deallocCount:\s*(\d+)', ' '.join(parts[3:]))
            assert counts, 'unknown pinned AllocStats representation'
            allocated,freed,live,requested = int(counts[1]),int(counts[2]),int(parts[2]),None
            scope = 'Nim ARC allocator only; native provider allocations excluded'
        else:
            assert parts[0] == 'ALLOC' and len(parts) == 6
            allocated,freed,live,requested = map(int,parts[2:])
            scope = 'Odin context allocator; backend/OS allocations outside this allocator excluded'
        assert allocated == freed and abs(live) <= 65536, 'unsettled application ownership'
        return dict(calls_per_operation=allocated/iterations,frees_per_operation=freed/iterations,
                    live_delta_bytes=live,requested_bytes_per_operation=None if requested is None else requested/iterations,scope=scope)
    assert not allocations and len(batches) == samples and len(latencies) == latency
    assert all(len(parts) == 3 and int(parts[1]) == iterations and int(parts[2]) > 0 for parts in batches)
    assert all(len(parts) == 2 and int(parts[1]) > 0 for parts in latencies)
    return dict(batch_ns_per_operation=[int(parts[2])/iterations for parts in batches],
                single_operation_ns=[int(parts[1]) for parts in latencies],peak_rss_bytes=int(ending[0][2]))


# Run one fresh native process with exact raw observations, optional Linux CPU affinity and bounded work.
def native(value,mode,language,iterations,samples,latency,cpu,instrumented=False,label='measurement'):
    suffix = '-alloc' if instrumented else ''
    credentials = [data.hex() for pair in value['credentials'] for data in pair]
    command = [str(BUILD/(language+suffix)),'bench',mode,value['path'],*credentials,str(iterations),str(samples),str(latency)]
    if cpu is not None:
        # Every candidate/calibration/allocation child inherits the same allowed Linux CPU.
        command = ['taskset','-c',str(cpu),*command]
    folder = RAW/f'{label}-{value["name"]}-{mode}-{language}-{time.time_ns()}'
    folder.mkdir(parents=True)
    result = subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=120)
    (folder/'stdout.log').write_text(result.stdout)
    (folder/'stderr.log').write_text(result.stderr)
    assert result.returncode == 0, (language,mode,result.returncode,result.stderr[-2000:])
    observation = parse(result.stdout,value,iterations,samples,latency,instrumented,language)
    observation['raw'] = str(folder.relative_to(ROOT))
    observation['command'] = command
    return observation


# Produce a compact same-host table without treating backend performance or LOC as a language-only result.
def markdown(report):
    lines = ['# Checked complete-report and guarantee workload','',
             f'Host: {report["platform"]}. Nim: checked ARC/Clang LTO only.',
             f'Processes/case/candidate: {report["processes"]}; batches/process: {report["samples"]}; individual latencies/process: {report["latency"]}.',
             '','Times below are median µs/operation across native batch averages. Individual p95 is separate.',
             '','| Report | Stage | Nim µs | Odin µs | Mojo µs | Nim p95 µs | Odin p95 µs | Mojo p95 µs |',
             '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for case in report['cases']:
        medians = [case['languages'][lang]['throughput']['median']/1000 for lang in LANGUAGES]
        tails = [case['languages'][lang]['latency']['p95']/1000 for lang in LANGUAGES]
        lines.append('| '+case['name']+' | '+case['mode']+' | '+' | '.join(f'{value:.3f}' for value in medians+tails)+' |')
    lines += ['','`owned` includes capture, canonical re-emission and last-owner release. `hash` includes the',
              'normative guarantee domain. `verify2` verifies two distinct prepared ordinary-key credentials.',
              '`pipeline` includes all these operations together. No startup, file I/O or credential imports are timed.',
              '','Nim/Mojo use the pinned BoringSSL primitive bridge; Odin uses pinned core crypto. Verification',
              'differences include provider choice. The unresolved small-order Ed25519 acceptance policy remains a gate.',
              '','Allocation observations, exact commands, source/binary/input hashes, affinity, toolchains,',
              'raw paths and provider provenance are retained in `results.json`. Counter scopes differ; Mojo has no public allocation-call counter.']
    return '\n'.join(lines)+'\n'


# Calibrate once per stage, rotate candidate order, then retain repeated native samples and separate allocation observations.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build',action='store_true')
    parser.add_argument('--build-only',action='store_true')
    parser.add_argument('--processes',type=int,default=3)
    parser.add_argument('--samples',type=int,default=7)
    parser.add_argument('--latency',type=int,default=128)
    parser.add_argument('--target-ms',type=float,default=20)
    parser.add_argument('--case',action='append',choices=('official','minimal','typical','maximum-metadata','maximum-payload','maximum-auth','maximum-lookup'))
    parser.add_argument('--mode',action='append',choices=MODES)
    args = parser.parse_args()
    assert 1 <= args.processes <= 9 and 1 <= args.samples <= 31 and 1 <= args.latency <= 256 and 1 <= args.target_ms <= 1000
    BUILD.mkdir(parents=True,exist_ok=True)
    helpers,compile_commands = ([],{lang:[list(map(str,commands(lang,instrumented)[0])) for instrumented in (False,True)] for lang in LANGUAGES}) if args.skip_build else build()
    if args.build_only:
        return
    receipt = json.loads((ROOT/'build/bench/report-observers.json').read_text())
    # A recorded non-LTO observer build must match the actual source and loaded libraries.
    for group in ('sources','binaries'):
        for path,digest in receipt[group].items():
            assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest, ('observer receipt mismatch',path)
    before_sources = source_hashes()
    before_binaries = {lang+suffix:hashlib.sha256((BUILD/(lang+suffix)).read_bytes()).hexdigest() for lang in LANGUAGES for suffix in ('','-alloc')}
    provider,values = fixtures()
    cpu = min(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else None
    report = dict(schema=1,complete=False,started_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
                  platform=platform.platform(),machine=platform.machine(),python=sys.version,cpu=cpu,
                  processes=args.processes,samples=args.samples,latency=args.latency,target_batch_ms=args.target_ms,
                  helper_commands=receipt['commands'],observer_receipt=receipt,compile_commands=compile_commands,source_hashes=before_sources,
                  binary_sha256=before_binaries,openssl_fixture_provider=provider,nim_lto=True,
                  toolchains={name:subprocess.check_output(command,text=True,stderr=subprocess.STDOUT).strip()
                              for name,command in {'nim':['nim','--version'],'odin':['odin','version'],
                                                   'mojo':[compiler(),'--version'],'clang':['clang','--version']}.items()},cases=[])
    rng = random.Random(0x4C544F5245504F5254)
    for value in values:
        if args.case and value['name'] not in args.case:
            continue # Focused smoke runs remain explicitly labelled by their actual case selection.
        path = BUILD/(value['name']+'.bin');path.write_bytes(value['wire']);value['path']=str(path)
        for mode in args.mode or MODES:
            probes = {lang:native(value,mode,lang,64,3,0,cpu,label='calibration') for lang in LANGUAGES}
            fastest = min(statistics.median(observation['batch_ns_per_operation']) for observation in probes.values())
            iterations = max(1,min(20000000,math.ceil(args.target_ms*1000000/fastest)))
            observations = {lang:[] for lang in LANGUAGES}
            orders = []
            base_order = list(LANGUAGES);rng.shuffle(base_order)
            for process in range(args.processes):
                # Rotate one seeded shuffled order so each candidate occupies every position in three processes.
                shift = process % len(LANGUAGES)
                order = base_order[shift:]+base_order[:shift];orders.append(order)
                for lang in order:
                    observations[lang].append(native(value,mode,lang,iterations,args.samples,args.latency,cpu))
            record = dict(name=value['name'],mode=mode,wire_bytes=len(value['wire']),wire_sha256=hashlib.sha256(value['wire']).hexdigest(),
                          message_hex=value['message'].hex(),credentials=[{'public':key.hex(),'signature':signature.hex()} for key,signature in value['credentials']],
                          iterations=iterations,calibration=probes,process_orders=orders,languages={})
            for lang in LANGUAGES:
                observed = observations[lang]
                allocation = native(value,mode,lang,512,1,0,cpu,True,label='allocation')
                # Only explicit owner operations are expected to allocate in the application allocators.
                if lang != 'mojo':
                    assert (allocation['calls_per_operation'] > 0) == (mode in ('owned','pipeline')), (lang,mode,allocation)
                record['languages'][lang] = dict(throughput=distribution([x for item in observed for x in item['batch_ns_per_operation']]),
                    latency=distribution([x for item in observed for x in item['single_operation_ns']]),observations=observed,allocation=allocation)
            report['cases'].append(record)
            print('PASS',value['name'],mode,*(f'{lang}={record["languages"][lang]["throughput"]["median"]/1000:.3f}us' for lang in LANGUAGES),flush=True)
            (BUILD/'results.partial.json').write_text(json.dumps(report,indent=2)+'\n')
    assert before_sources == source_hashes(), 'sources changed during benchmark'
    assert before_binaries == {name:hashlib.sha256((BUILD/name).read_bytes()).hexdigest() for name in before_binaries}, 'binaries changed during benchmark'
    for path,digest in receipt['binaries'].items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest, ('observer changed during measurement',path)
    report['complete'] = True
    report['finished_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    (BUILD/'results.json').write_text(json.dumps(report,indent=2)+'\n')
    (BUILD/'results.md').write_text(markdown(report))


# Importing evidence-parsing helpers must not compile code or run performance experiments.
if __name__ == '__main__':
    main()
