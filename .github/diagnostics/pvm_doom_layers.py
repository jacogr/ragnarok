#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Private, unmerged orchestration of the unchanged canonical DOOM tick driver and controls.

The approved JSON fixes every source, build and process. --inspect is source-only; --run is
restricted to the one explicitly dispatched native ARM CI job and approved manifest digest.
This diagnostic does not publish a canonical full-cohort performance report.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import statistics
import struct
import subprocess
import sys
import tarfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools'))
from native_checks import NativeChecks
from pvm_ci_performance import PerformanceRunner, execution_environment, command_record
from pvm_native_ci import host_identity
from setup_nimony import installed, cache_directory

MANIFEST = ROOT/'.github/diagnostics/pvm_doom_layers.json'
OUTPUT = ROOT/'build/pvm-doom-layer-diagnostic'
STAGE = OUTPUT/'stage'
COMPILATION = OUTPUT/'compiler'
DRIVER = 'tests/performance/pvm_doom.nim'
POLICIES = ('interpreted', 'jit')


def digest(path):
    """Seal exact regular bytes, refusing redirection through symlinks."""
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError('Missing or redirected sealed file: '+str(path))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    """Checkpoint metadata atomically without accepting stale successful evidence."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name+'.tmp')
    temporary.write_text(json.dumps(value, indent=2)+'\n')
    temporary.replace(path)


def git(*arguments):
    """Read immutable source objects through Git, without changing any catalog or ref."""
    return subprocess.check_output(['git', *arguments], cwd=ROOT)


def verify(seals):
    """A changed compiler, source, input or image invalidates this attempt before the next process."""
    for name, expected in seals.items():
        if digest(name) != expected:
            raise ValueError('Sealed file changed: '+str(name))


def closure(folder):
    """Record every physical source file, not just the declared patch's edited lines."""
    result = {}
    for path in sorted(Path(folder).rglob('*')):
        if path.is_symlink():
            raise ValueError('Redirected materialized source: '+str(path))
        if path.is_file():
            result[path.relative_to(folder).as_posix()] = digest(path)
    return result


def git_file_seals(ref):
    """Bind the full regular Git tree to SHA256 bytes in one batch, including unedited files."""
    entries={}
    for entry in git('ls-tree','-r','-z',ref).split(b'\0'):
        if entry:
            metadata,name=entry.split(b'\t',1)
            mode,kind,oid=metadata.split()
            if kind==b'commit':
                continue  # Pinned submodules are admitted separately; staging has no borrowed checkout.
            if kind!=b'blob' or mode not in (b'100644',b'100755'):
                raise ValueError('Unsupported redirected Git source: '+os.fsdecode(name))
            entries[os.fsdecode(name)]=oid
    objects=list(dict.fromkeys(entries.values()))
    data=subprocess.check_output(['git','cat-file','--batch'],cwd=ROOT,
                                 input=b'\n'.join(objects)+b'\n')
    cursor=0
    values={}
    for oid in objects:
        end=data.index(b'\n',cursor)
        found,kind,size=data[cursor:end].split()
        size=int(size)
        cursor=end+1
        if found!=oid or kind!=b'blob' or size<0 or size>len(data)-cursor-1 or data[cursor+size]!=10:
            raise ValueError('Incomplete immutable Git blob batch')
        values[oid]=hashlib.sha256(data[cursor:cursor+size]).hexdigest()
        cursor+=size+1
    if cursor!=len(data):
        raise ValueError('Trailing immutable Git batch data')
    return {name:values[oid] for name,oid in entries.items()}


def expected_order():
    """Encode the root-approved chronology, including both reference passes and all A anchors."""
    rows = [('reference-before', 'reference', 'reference')]
    for policy in POLICIES:
        rows += [('AA-before', 'A', policy)]*2
    for policy in POLICIES:
        rows += [('forward', variant, policy) for variant in 'ABCD']
    for policy in POLICIES[::-1]:
        rows += [('reverse', variant, policy) for variant in 'DCBA']
    for policy in POLICIES[::-1]:
        rows += [('AA-after', 'A', policy)]*2
    return rows+[('reference-after', 'reference', 'reference')]


def inspect():
    """Validate source/contract only; this entry never builds, prepares or executes a guest."""
    plan = json.loads(MANIFEST.read_text())
    if (os.environ.get('GITHUB_ACTIONS')=='true' and
            os.environ.get('PVM_DIAGNOSTIC_APPROVED_MANIFEST')!=digest(MANIFEST)):
        raise ValueError('Dispatch manifest differs from the root-inspected bytes')
    if plan['schema'] != 'pvm-doom-layer-attempt-v1':
        raise ValueError('Foreign diagnostic contract')
    variants = plan['variants']
    if set(variants) != set('ABCD') or plan['builds']['order'] != ['A1', 'A2', 'B', 'C', 'D']:
        raise ValueError('Changed source/build matrix')
    for variant, item in variants.items():
        if git('rev-parse', item['commit']+'^{tree}').decode().strip() != item['tree']:
            raise ValueError('Wrong immutable tree: '+variant)
        for name, expected in item['key_source_sha256'].items():
            value = hashlib.sha256(git('show', item['commit']+':'+name)).hexdigest()
            if value != expected:
                raise ValueError('Source contract mismatch: '+variant+' '+name)
    actual = [(r['group'], r['variant'], r['policy']) for r in plan['timing']['order']]
    if (actual != expected_order() or [r['index'] for r in plan['timing']['order']] != list(range(26))
            or any(r['calls'] != 13 for r in plan['timing']['order'])):
        raise ValueError('Changed chronological timing matrix')
    wanted_controls = [(v, p, k) for v in 'ABCD' for p in POLICIES
                       for k in ('positive', 'assertions', 'state', 'events')]
    wanted_controls += [('reference', 'reference', k) for k in ('positive', 'assertions', 'state', 'events')]
    if [(r['variant'], r['policy'], r['kind']) for r in plan['controls']['order']] != wanted_controls:
        raise ValueError('Changed preflight control matrix')
    for name, expected in plan['harness_files'].items():
        if digest(ROOT/name) != expected:
            raise ValueError('Private harness changed: '+name)
    # Only these temporary diagnostic files may differ from the frozen production D tree.
    allowed = {'.github/workflows/ci.yml', '.github/diagnostics/pvm_doom_layers.py',
               '.github/diagnostics/pvm_doom_layers.json'}
    changed = set(git('diff', '--name-only', variants['D']['commit'], 'HEAD').decode().splitlines())
    if not changed <= allowed or git('status', '--porcelain').strip():
        raise ValueError('Diagnostic branch has unexpected or uncommitted changes')
    for variant in ('C', 'D'):
        if subprocess.run(['git', 'merge-base', '--is-ancestor', variants[variant]['commit'], 'HEAD'], cwd=ROOT).returncode:
            raise ValueError('Preserved source is not in diagnostic ancestry: '+variant)
    return plan


class DurableChecks(NativeChecks):
    """Keep the maintained build primitive and retain both streams even on the first timeout."""
    def __init__(self, folder):
        super().__init__(folder)
        self.folder.mkdir(parents=True, exist_ok=True)

    def command(self, arguments, name, environment=None, cwd=ROOT, timeout=180):
        """Record immutable invocation inputs around a bounded owned process group."""
        arguments = [str(x) for x in arguments]
        environment = dict(os.environ) if environment is None else environment
        inputs = {}
        executable = Path(arguments[0])
        if executable.is_absolute() and executable.is_file():
            inputs[str(executable)] = digest(executable)
        directory = environment.get('RAGNAROK_PVM_DOOM_INPUT')
        if directory:
            for path in sorted(Path(directory).iterdir()):
                if path.is_file() or path.is_symlink():
                    inputs[str(path)] = digest(path)
        rom = environment.get('RAGNAROK_PVM_DOOM_ROM')
        if rom:
            inputs[rom] = digest(rom)
        # Reference blob is another direct input; do not infer it from a mutable directory name.
        if len(arguments) > 2 and arguments[1] == 'run':
            inputs[arguments[2]] = digest(arguments[2])
        knobs = {k:v for k,v in environment.items() if k.startswith('RAGNAROK_PVM_')}
        modes={name:oct(stat.S_IMODE(Path(name).stat().st_mode)) for name in inputs}
        save(self.folder/(name+'-attempt.json'), dict(command=arguments, cwd=str(cwd),
             timeout=timeout, benchmark_environment=knobs, input_sha256=inputs,input_modes=modes))
        verify(inputs)
        started = time.monotonic()
        process = subprocess.Popen(arguments, cwd=cwd, env=environment, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        timed_out = False
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Kill/reap compiler children as well; a partial timeout cannot become a refusal pass.
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass  # The child may have exited just after the timeout, but its streams still need reaping.
            stdout, stderr = process.communicate()
        elapsed = round(time.monotonic()-started, 6)
        (self.folder/(name+'.stdout')).write_bytes(stdout)
        (self.folder/(name+'.stderr')).write_bytes(stderr)
        output = (stdout+stderr).decode('utf-8', errors='strict')
        log = self.folder/(name+'.log')
        log.write_text(output)
        result = dict(command=arguments, exit_code=process.returncode, elapsed_seconds=elapsed,
                      log=str(log.relative_to(ROOT)), output=output)
        save(self.folder/(name+'-result.json'), dict(command_record(result), timed_out=timed_out,
             stdout_sha256=digest(self.folder/(name+'.stdout')),
             stderr_sha256=digest(self.folder/(name+'.stderr')), input_sha256=inputs,input_modes=modes))
        verify(inputs)
        if modes!={name:oct(stat.S_IMODE(Path(name).stat().st_mode)) for name in inputs}:
            raise ValueError('Process changed a sealed input mode: '+str(log))
        if timed_out:
            raise TimeoutError('First process timeout retained: '+str(log))
        return result


def elf_identity(path):
    """Read bounded ELF64 ARM sections/segments for deterministic-build diagnosis, without execution."""
    data = Path(path).read_bytes()
    if len(data) < 64 or data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 183:
        raise ValueError('Expected native little-endian ELF64 ARM image')
    phoff, shoff = struct.unpack_from('<QQ', data, 32)
    phsize, phnum, shsize, shnum, names_index = struct.unpack_from('<HHHHH', data, 54)
    if (phsize != 56 or shsize != 64 or not 0 < shnum < 65535 or names_index >= shnum
            or phoff+phsize*phnum > len(data) or shoff+shsize*shnum > len(data)):
        raise ValueError('Unsupported or malformed ELF tables')
    def span(offset, size):
        if offset > len(data) or size > len(data)-offset:
            raise ValueError('ELF extent outside image')
        return data[offset:offset+size]
    headers = [struct.unpack_from('<IIQQQQIIQQ', data, shoff+i*64) for i in range(shnum)]
    names = span(headers[names_index][4], headers[names_index][5])
    sections = {}
    for index, header in enumerate(headers):
        at, kind, flags, address, offset, size, *_ = header
        end = names.find(b'\0', at)
        if at >= len(names) or end < at:
            raise ValueError('Invalid ELF section name')
        name = names[at:end].decode('ascii')
        body = b'' if kind == 8 else span(offset, size)
        sections[str(index)+':'+name] = dict(name=name, type=kind, flags=flags,
            address=address, size=size, sha256=hashlib.sha256(body).hexdigest())
    segments = []
    for index in range(phnum):
        kind, flags, offset, address, _, size, memory, align = struct.unpack_from('<IIQQQQQQ', data, phoff+index*56)
        if kind == 1:
            segments.append(dict(flags=flags, address=address, bytes=size, memory=memory,
                alignment=align, sha256=hashlib.sha256(span(offset,size)).hexdigest()))
    return dict(sha256=digest(path), sections=sections, loadable_segments=segments)


def image_difference(first, second):
    """Expose code/loadable/metadata differences but never waive whole-image determinism."""
    a, b = elf_identity(first), elf_identity(second)
    names = sorted(set(a['sections']) | set(b['sections']))
    changed = [name for name in names if a['sections'].get(name) != b['sections'].get(name)]
    text = lambda item: [v for v in item['sections'].values() if v['name']=='.text']
    return dict(whole_image_equal=a['sha256']==b['sha256'], code_equal=text(a)==text(b),
        loadable_equal=a['loadable_segments']==b['loadable_segments'],
        changed_sections=changed,
        metadata_differences=[n for n in changed if not ((a['sections'].get(n,{})|b['sections'].get(n,{})).get('flags',0)&2)
            or (a['sections'].get(n,{})|b['sections'].get(n,{})).get('name','').startswith(('.note','.comment','.debug'))],
        first=a, second=b)


def determinism_gate(first, second, receipt):
    """Persist mismatch detail and stop even if only non-loadable metadata differs."""
    difference=image_difference(first,second)
    save(receipt,difference)
    if not difference['whole_image_equal']:
        raise ValueError('A build nondeterminism: stop before controls or timing')
    return difference


def materialize(variant, plan, seals):
    """Reconstruct immutable Git source at the same owned physical path for every compile."""
    archive = OUTPUT/'sources'/(variant+'.tar')
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        subprocess.run(['git','archive','--format=tar','--output='+str(archive),
                        plan['variants'][variant]['commit']], cwd=ROOT, check=True)
        seals[archive]=digest(archive)
    elif archive not in seals:
        raise ValueError('Refuse a pre-existing unsealed source archive')
    verify({archive:seals[archive]})
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir()
    expected=git_file_seals(plan['variants'][variant]['commit'])
    with tarfile.open(archive) as source:
        for member in source:
            name = Path(member.name)
            if name.is_absolute() or '..' in name.parts or not (member.isdir() or member.isfile()):
                raise ValueError('Unexpected source archive member: '+member.name)
            source.extract(member, STAGE, filter='data')
    if closure(STAGE) != expected:
        raise ValueError('Materialized source differs from archived closure')
    return archive, expected


def build_images(plan, compiler, report, seals):
    """Compile A twice before any guest process, then B/C/D with identical fresh build paths."""
    images = {}
    build_environment = execution_environment()
    save(OUTPUT/'build-environment.json', {k:v for k,v in build_environment.items()
         if k in ('PATH','CC','CXX','CFLAGS','CPPFLAGS','LDFLAGS','CPATH','LIBRARY_PATH',
                  'NIMFLAGS','NIMONY','NIMPRETTY','SOURCE_DATE_EPOCH','TMPDIR','LANG','LC_ALL')})
    for label in plan['builds']['order']:
        verify(seals)
        variant = 'A' if label.startswith('A') else label
        record = OUTPUT/'builds'/label
        record.mkdir(parents=True)
        archive, sources = materialize(variant, plan, seals)
        save(record/'source-before.json', dict(commit=plan['variants'][variant]['commit'],
             tree=plan['variants'][variant]['tree'], archive_sha256=digest(archive), files=sources))
        if COMPILATION.exists():
            shutil.rmtree(COMPILATION)
        checks = DurableChecks(COMPILATION)
        row, binary = checks.build(compiler, STAGE/DRIVER, 'guest',
            defines=['pvmArm64Jit','pvmArm64JitOwnerReceipt'],
            cflags=['-I'+str(STAGE/'tests/performance'),'-I'+str(STAGE/'native/pvm_jit')],
            environment=build_environment)
        # Retain the complete build streams and all generated source before the next fresh cache.
        for path in COMPILATION.glob('guest-build*'):
            shutil.copy2(path, record/path.name)
        cache = cache_directory(compiler, COMPILATION, 'guest')
        generated = {}
        for path in sorted(cache.rglob('*')):
            if path.is_file():
                relative = path.relative_to(cache)
                generated[str(relative)] = dict(sha256=digest(path), bytes=path.stat().st_size)
                if path.suffix in ('.c','.h','.nif','.idx'):
                    target = record/'generated'/relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(path,target)
        save(record/'cache-files.json', generated)
        actual = closure(STAGE)
        save(record/'source-after.json', dict(files=actual, archive_sha256=digest(archive)))
        verify(seals)
        row['log'] = str((record/'guest-build.log').relative_to(ROOT))
        report['builds'].append(dict(label=label,variant=variant,run=command_record(row)))
        if row['exit_code'] or actual != sources or 'Error:' in row['output'] or 'FAILURE' in row['output']:
            raise ValueError('Build/source gate failed: '+label)
        wanted = [str(compiler),'c',*[x.replace('<fixed-stage>',str(STAGE)) for x in plan['build_profile']['flags']],
                  '--nimcache:'+str(cache),'--out:'+str(COMPILATION/'guest'),str(STAGE/DRIVER)]
        if row['command'] != wanted:
            raise ValueError('Actual compile profile differs from approved contract')
        image = record/'guest'
        shutil.copy2(binary,image)
        save(record/'elf.json', elf_identity(image))
        # Disassembly is evidence only; every variant still follows the unchanged timed order.
        disassembly = checks.command(['objdump','-d',str(image)],'disassembly-'+label)
        for path in COMPILATION.glob('disassembly-'+label+'*'):
            shutil.copy2(path,record/path.name)
        if disassembly['exit_code']:
            raise ValueError('Cannot retain linked-code evidence: '+label)
        if label == 'A1':
            images['A'] = image
        elif label == 'A2':
            determinism_gate(images['A'],image,OUTPUT/'A-determinism.json')
        else:
            images[variant] = image
        save(OUTPUT/'results.json',report)
    return images


def runner(folder, prepared, images, seals):
    """Bind canonical invocation/control/parse primitives to shared frozen preparation and one image."""
    folder.mkdir(parents=True,exist_ok=True)
    result = PerformanceRunner(folder,scope='doom')
    result.checks = DurableChecks(folder)
    result.doom_folder, result.doom_blob, result.rom = prepared.doom_folder, prepared.doom_blob, prepared.rom
    result.references, result.images, result.seals = dict(prepared.references), images, dict(seals)
    return result


def metric(row, phase, clock):
    """Keep the established cold and reused windows without dropping any stored sample."""
    values = row['parsed']['invocation']['samples']
    return values[0][clock] if phase=='cold' else statistics.median(x[clock] for x in values[3:])


def classify(anchors, forward_a, reverse_a, forward_b, reverse_b):
    """Require both directional effects outside the full six-A drift envelope; never pick a pair."""
    low, high = min(anchors), max(anchors)
    span = high/low-1
    effects = [forward_b/forward_a-1,reverse_b/reverse_a-1]
    outside = (max(forward_b,reverse_b)<low or min(forward_b,reverse_b)>high)
    consistent = effects[0]*effects[1]>0
    passed = outside and consistent and min(abs(x) for x in effects)>span
    return dict(A_min_ns=low,A_max_ns=high,A_relative_span=span,forward_change=effects[0],
                reverse_change=effects[1],outside_full_controls=passed,
                classification=('lower' if effects[0]<0 else 'higher') if passed else 'unresolved')


def summarize(rows):
    """Preserve all orders and native work while reporting paired layers and full control distributions."""
    if [(r['group'],r['variant'],r['policy']) for r in rows] != expected_order():
        raise ValueError('Cannot summarize an incomplete/reordered attempt')
    result = []
    for policy in POLICIES:
        for phase in ('cold','reused'):
            for clock in ('cpu_ns','wall_ns'):
                anchors = [metric(r,phase,clock) for r in rows if r['variant']=='A' and r['policy']==policy]
                if len(anchors)!=6:
                    raise ValueError('Missing full A control envelope')
                group = {(r['group'],r['variant']):r for r in rows if r['policy']==policy and r['group'] in ('forward','reverse')}
                for numerator,denominator in (('B','A'),('C','A'),('D','C'),('D','B'),('D','A')):
                    values = [metric(group[direction,variant],phase,clock) for direction in ('forward','reverse') for variant in (denominator,numerator)]
                    fa,fb,ra,rb = values
                    observation = dict(policy=policy,phase=phase,clock=clock,comparison=numerator+'/'+denominator,
                        A_anchors_ns=anchors,forward_denominator_ns=fa,forward_numerator_ns=fb,
                        reverse_denominator_ns=ra,reverse_numerator_ns=rb,forward_change=fb/fa-1,reverse_change=rb/ra-1)
                    observation['control_qualification']=classify(anchors,fa,ra,fb,rb)
                    observation['control_source']='All six A anchors; C/B contrasts have no separate repeated same-source envelope.'
                    observation['native'] = {direction:{variant:group[direction,variant]['parsed']['native'] for variant in (denominator,numerator)} for direction in ('forward','reverse')}
                    observation['native_aggregate_equal'] = all(
                        observation['native'][direction][denominator] == observation['native'][direction][numerator]
                        for direction in ('forward','reverse'))
                    if not observation['native_aggregate_equal']:
                        observation['interpretation_limit']='Whole-process native work differs; retain all timing rows without replacement or causal speed attribution.'
                    result.append(observation)
    return result


def interactions(rows):
    """Expose factorial layer interactions without a new timing run or acceptance shortcut."""
    result=[]
    for policy in POLICIES:
        for phase in ('cold','reused'):
            for clock in ('cpu_ns','wall_ns'):
                item=dict(policy=policy,phase=phase,clock=clock)
                for direction in ('forward','reverse'):
                    values={r['variant']:metric(r,phase,clock) for r in rows
                            if r['policy']==policy and r['group']==direction}
                    item[direction]=dict(absolute_ns=values,
                        guard_layer_ratio=values['B']/values['A'],
                        guard_with_artifact_ratio=values['D']/values['C'],
                        interaction_ratio=(values['D']/values['C'])/(values['B']/values['A']))
                result.append(item)
    return result


def run(plan):
    """Execute exactly one source-approved native CI attempt, keeping the first failure durable."""
    if (os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('GITHUB_JOB')!='paired-doom'
            or os.environ.get('PVM_DIAGNOSTIC_APPROVED_MANIFEST')!=digest(MANIFEST)):
        raise RuntimeError('Requires the explicit root-approved CI manifest dispatch')
    if git('rev-parse','HEAD').decode().strip()!=os.environ.get('GITHUB_SHA'):
        raise ValueError('Checkout differs from dispatch head')
    if OUTPUT.exists():
        raise ValueError('Refuse stale/private attempt output; no retry in place')
    OUTPUT.mkdir(parents=True)
    report = dict(schema='pvm-doom-layer-diagnostic-v1',status='running',manifest_sha256=digest(MANIFEST),
                  diagnostic_head=os.environ['GITHUB_SHA'],builds=[],controls=[],runs=[])
    try:
        host = host_identity()
        if host['system']!='Linux' or host['architecture']!='arm64':
            raise ValueError('Requires one real Linux ARM64 host')
        compiler,_ = installed()
        if digest(compiler)!=plan['build_profile']['linux_arm_compiler_sha256']:
            raise ValueError('Wrong pinned compiler bytes')
        report['host'],report['compiler_sha256'] = host,digest(compiler)
        report['ci']={k:os.environ.get(k) for k in ('GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT','GITHUB_SHA',
                      'GITHUB_REF','GITHUB_REPOSITORY','GITHUB_JOB','GITHUB_WORKFLOW')}
        report['tool_versions'] = {name:subprocess.check_output(args,text=True) for name,args in
            (('clang',['clang','--version']),('rust',['rustup','run','1.99.0','rustc','--version','--verbose']))}
        save(OUTPUT/'manifest.json',plan)
        save(OUTPUT/'host-before.json',dict(host=host,loadavg=Path('/proc/loadavg').read_text(),process_names=subprocess.check_output(['ps','-e','-o','comm='],text=True)))
        prepared = PerformanceRunner(OUTPUT/'preparation',scope='doom')
        prepared.folder.mkdir()
        prepared.checks = DurableChecks(prepared.folder)
        prepared.rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
        # Match the canonical producer's unchanged-source sealing around every command/process.
        for name,expected in git_file_seals('HEAD').items():
            path=ROOT/name
            if digest(path)!=expected:
                raise ValueError('Outer source differs from diagnostic commit: '+name)
            prepared.seals[path]=expected
        prepared.seals[compiler]=digest(compiler)
        save(OUTPUT/'root-source-seals.json',{str(k):v for k,v in prepared.seals.items()})
        prepared.prepare_doom()
        # Fresh canonical preparation stays writable and hash-sealed; copy2 negatives inherit these modes.
        prepared_modes={path.name:oct(stat.S_IMODE(path.stat().st_mode)) for path in prepared.doom_folder.iterdir() if path.is_file()}
        save(OUTPUT/'prepared-file-modes.json',prepared_modes)
        for path in prepared.doom_folder.iterdir():
            if path.is_file() and path.suffix in ('.expected','.events') and not path.stat().st_mode & stat.S_IWUSR:
                raise ValueError('Fresh oracle lacks owner-write mode for canonical private negative copies: '+str(path))
        for name,expected in plan['preparation']['expected_frozen_input_sha256'].items():
            if '/doom/prepared/' in name:
                path = prepared.doom_folder/Path(name).name
            elif name.endswith('/doom/doom.polkavm'):
                path = prepared.doom_blob
            else:
                path = prepared.rom
            if digest(path)!=expected:
                raise ValueError('Frozen canonical preparation changed: '+name)
        report['preparation'] = prepared.report
        images = build_images(plan,compiler,report,prepared.seals)
        report['image_pairs']={name:image_difference(images[a],images[b])
                               for name,a,b in (('A-C','A','C'),('B-D','B','D'))}
        seals = dict(prepared.seals)
        for path in (compiler,MANIFEST,*images.values(),OUTPUT/'builds/A2/guest',
                     *(ROOT/name for name in plan['harness_files'])):
            seals[Path(path)] = digest(path)
        save(OUTPUT/'immutable-seals.json',{str(k):v for k,v in seals.items()})
        case = dict(case_id='doom-tick',case='tick',limit=0,family='doom',native_required=[])
        # Every native policy gets the existing complete canonical preflight control sequence.
        for variant in 'ABCD':
            controlled = runner(OUTPUT/'controls'/variant,prepared,{'doom':images[variant]},seals)
            for policy in POLICIES:
                controlled.controls(case,policy)
            report['controls'] += [dict(variant=variant,**r) for r in controlled.report['controls']]
            save(OUTPUT/'results.json',report)
        controlled = runner(OUTPUT/'controls/reference',prepared,{},seals)
        controlled.controls(case,'reference')
        report['controls'] += [dict(variant='reference',**r) for r in controlled.report['controls']]
        actual_controls = [(r['variant'],r['role'],r['kind']) for r in report['controls']]
        if actual_controls != [(r['variant'],r['policy'],r['kind']) for r in plan['controls']['order']]:
            raise ValueError('Actual preflight controls differ from contract')
        for item in plan['timing']['order']:
            variant,policy = item['variant'],item['policy']
            measured = runner(OUTPUT/'timed'/f"{item['index']:02}-{item['group']}-{variant}-{policy}",
                              prepared,{} if policy=='reference' else {'doom':images[variant]},seals)
            arguments,environment,_ = measured.invocation(case,policy)
            observed = measured.command(arguments,'process',environment)
            parsed = measured.parse(observed['output'],case,policy)['doom-tick']
            report['runs'].append(dict(item,parsed=parsed,run=command_record(observed),
                                      image_sha256=digest(Path(arguments[0]))))
            save(OUTPUT/'results.json',report)
        report['comparisons'] = summarize(report['runs'])
        report['interactions'] = interactions(report['runs'])
        verify(seals)
        report['status']='completed'
        save(OUTPUT/'host-after.json',dict(host=host_identity(),loadavg=Path('/proc/loadavg').read_text(),process_names=subprocess.check_output(['ps','-e','-o','comm='],text=True)))
        with (OUTPUT/'calls.csv').open('w') as output:
            writer=csv.DictWriter(output,fieldnames=['index','group','variant','policy','sample','cpu_ns','wall_ns'])
            writer.writeheader()
            for row in report['runs']:
                for sample in row['parsed']['invocation']['samples']:
                    writer.writerow({**{k:row[k] for k in ('index','group','variant','policy')},**sample})
        lines=['# Paired DOOM layer diagnostic','',
               'All predeclared processes completed. This is not automatic performance acceptance or lgtm.',
               '', '| Policy | Phase | Clock | Contrast | Forward % | Reverse % | Full six-A span % | Outside controls | Native work equal |',
               '|---|---|---|---|---:|---:|---:|---|---|']
        for item in report['comparisons']:
            control=item['control_qualification']
            lines.append(f"| {item['policy']} | {item['phase']} | {item['clock']} | {item['comparison']} | {100*item['forward_change']:+.3f} | {100*item['reverse_change']:+.3f} | {100*control['A_relative_span']:.3f} | {control['classification']} | {item['native_aggregate_equal']} |")
        lines+=['', 'The JSON retains all six A anchors, individual 13-call distributions, interactions and reference rows.',
                'All cold/reused CPU/wall effects remain separate. Native-work differences constrain interpretation, never select or replace a row.']
        (OUTPUT/'summary.md').write_text('\n'.join(lines)+'\n')
    except Exception as error:
        # Never resume, replace a row, or publish a completed comparison after the first failure.
        report.update(status='failed',error=repr(error))
        raise
    finally:
        save(OUTPUT/'results.json',report)
        files={str(p.relative_to(OUTPUT)):digest(p) for p in OUTPUT.rglob('*') if p.is_file() and p.name!='FILES.json'}
        save(OUTPUT/'FILES.json',files)


if __name__=='__main__':
    arguments=argparse.ArgumentParser(description=__doc__)
    mode=arguments.add_mutually_exclusive_group(required=True)
    mode.add_argument('--inspect',action='store_true')
    mode.add_argument('--run',action='store_true')
    selected=arguments.parse_args()
    contract=inspect()
    if selected.inspect:
        print(json.dumps(dict(status='source-inspection-passed',manifest_sha256=digest(MANIFEST),
              variants=contract['variants'],builds=contract['builds']['order'],timed_processes=26,calls=338)))
    else:
        run(contract)
