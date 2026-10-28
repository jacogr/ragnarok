#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""CI-only continuing DOOM parity through CLI-selected prepared engines, with bounded per-frame receipts."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess

from build_polkavm import build_native
from native_checks import NativeChecks, ROOT
from pvm_doom_attribution import BUILD as DOOM, event_hashes, run as prepare_doom
from pvm_guest_compare import unchanged
from pvm_guest_inputs import digest
from pvm_native_ci import host_identity
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-doom-backends'
DRIVER = ROOT/'tests/interop/pvm_doom_backends.nim'
BACKENDS = ('polkavm-interpreted', 'jit')


class Mismatch(ValueError):
    """The first differing frame/call remains actionable without uploading raw guest videos or memory."""


def rgba_frames(data, call, first):
    """Normalize the frozen BGRX host ABI to opaque RGBA exactly like the maintained upstream golden check."""
    event_hashes(data)  # Independently maintained framing/size/dimension checks precede payload slicing.
    frames, at = [], 0
    while at < len(data):
        kind, size = data[at], int.from_bytes(data[at+1:at+5], 'little')
        at += 5
        payload = data[at:at+size]
        at += size
        if kind == 1:
            rgba = bytearray(payload)
            rgba[0::4], rgba[2::4] = payload[2::4], payload[0::4]
            rgba[3::4] = b'\xff'*(640*400)
            frames.append(dict(index=first+len(frames), call=call, width=640, height=400,
                               rgba_sha256=hashlib.sha256(rgba).hexdigest()))
    return frames


def compare(left, right, calls):
    """Refuse the first missing/reordered/pixel-different frame, then every state and ordered host discrepancy."""
    if len(left['calls']) != calls or len(right['calls']) != calls:
        raise Mismatch('incomplete continuing call sequence')
    if not left['frames'] or len(left['frames']) != len(right['frames']):
        raise Mismatch('frame count mismatch')
    for index, (wanted, actual) in enumerate(zip(left['frames'], right['frames'])):
        if wanted['index'] != index or actual['index'] != index:
            raise Mismatch(f'frame {index}: missing or reordered index')
        for field in ('call', 'width', 'height', 'rgba_sha256'):
            if wanted[field] != actual[field]:
                raise Mismatch(f'frame {index}: {field} mismatch')
    for call, (wanted, actual) in enumerate(zip(left['calls'], right['calls'])):
        for field in ('state_sha256', 'events_sha256', 'hosts_sha256', 'gas'):
            if wanted[field] != actual[field]:
                raise Mismatch(f'call {call}: {field} mismatch')


def observation(output, folder, selected, count, pages, architecture):
    """Only complete native processes with honest requested/actual engine receipts supply comparison inputs."""
    lines = output.splitlines()
    if len(lines) != count+1 or lines[-1] != f'DOOM_SEQUENCE_OK,{selected},{count}':
        raise ValueError('incomplete DOOM backend process')
    result = dict(requested=selected, calls=[], frames=[])
    for call, line in enumerate(lines[:-1]):
        fields = line.split(',')
        if len(fields) != 10 or fields[:3] != ['DOOM_CALL', str(call), selected]:
            raise ValueError('foreign or reordered DOOM call receipt')
        numbers = fields[4:]
        if any(not n.isascii() or not n.isdecimal() or len(n)>20 or int(n)>=2**64 for n in numbers):
            raise ValueError('invalid DOOM policy counters')
        gas, fragments, native_calls, operations, built, supported = map(int, numbers)
        if built not in (0, 1) or supported not in (0, 1):
            raise ValueError('invalid DOOM availability flags')
        actual = fields[3]
        if selected == 'polkavm-interpreted':
            if actual != selected or any((fragments, native_calls, operations)):
                raise ValueError('foreign engine substituted or published native activity')
        elif architecture == 'arm64':
            if actual != 'jit' or not (built and supported and fragments and native_calls and operations):
                raise ValueError('missing positive ARM64 JIT execution')
        elif actual != 'interpreted' or supported or any((fragments, native_calls, operations)):
            raise ValueError('unavailable x86 JIT was mislabeled as native')
        state, events, hosts = (folder/f'call-{call}.{suffix}' for suffix in ('state','events','hosts'))
        if state.stat().st_size != 129+pages*4101 or hosts.stat().st_size > 512*1024:
            raise ValueError('incomplete state or unbounded host trace')
        if events.stat().st_size > 4*1024*1024:
            raise ValueError('unbounded host events')
        raw = events.read_bytes()
        frames = rgba_frames(raw, call, len(result['frames']))
        result['frames'].extend(frames)
        result['calls'].append(dict(call=call, actual=actual, gas=gas, fragments=fragments,
            native_calls=native_calls, native_operations=operations, jit_built=bool(built),
            jit_platform_supported=bool(supported), state_sha256=digest(state),
            events_sha256=event_hashes(raw)['sha256'], hosts_sha256=digest(hosts)))
    return result


def negative_frames(reference, candidate, count, pixel_frames):
    """Mutate receipts from actual executed output, including hashes recomputed from a changed real pixel."""
    rows = []
    variants = []
    changed = copy.deepcopy(candidate)
    changed['frames'] = pixel_frames
    variants.append(('changed-pixel', changed))
    changed = copy.deepcopy(candidate)
    changed['frames'].pop()
    variants.append(('omitted-frame', changed))
    changed = copy.deepcopy(candidate)
    if len(changed['frames']) > 1:
        changed['frames'].reverse()
    else:
        changed['frames'][0]['index'] += 1  # A one-call pilot still proves index/order admission.
    variants.append(('reordered-frame', changed))
    for name, changed in variants:
        try:
            compare(reference, changed, count)
        except Mismatch as error:
            rows.append(dict(control=name, refused=True, diagnostic=str(error)))
        else:
            raise ValueError('mutation was accepted: '+name)
    return rows


def run():
    """Execute on isolated native CI only, size a bounded pilot explicitly and retain incomplete evidence on failures."""
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('DOOM shared-backend execution is CI-only to preserve local timing windows')
    requested = os.environ.get('PVM_DOOM_CALLS', '2')
    if requested not in ('1', '2'):
        raise ValueError('DOOM backend calls must be the explicit one-call pilot or two-call sequence')
    count = int(requested)
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(status='incomplete', protocol='doom-shared-backends-v1', calls=count,
                  warmup_ticks=1320, builds=[], runs=[], controls=[])
    checks = NativeChecks(BUILD)

    def save():
        """Persist current evidence before work and after every process, including the first refusal diagnostic."""
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        lines = [f"DOOM shared-backend check: {report['status']}", '',
            f"Native architecture: {report.get('host', {}).get('architecture', 'unqualified')}; continuing calls: {count}.",
            'Same pinned frame-1320 snapshot restored once; no host clock, RNG, audio or key input varies.',
            'x86 requested jit uses interpreted fallback; positive native JIT is required only on ARM64.', '']
        for row in report['runs']:
            observed = row.get('observed')
            if observed:
                lines.append(f"- Requested `{observed['requested']}`; actual `{observed['calls'][0]['actual']}`; frames: {len(observed['frames'])}.")
        if report.get('identities'):
            lines += ['', 'PolkaVM pin: `'+report['polkavm']['commit']+'`.',
                'Nimony pin: `'+report['toolchain']['commit']+'`.',
                'Initial snapshot SHA256: `'+report['identities']['build/tests/pvm-doom/prepared/tick.input']+'`.',
                'WAD SHA256: `'+report['assets']['files']['examples/doom/roms/doom1.wad']+'`.',
                'Linked guest SHA256: `'+report['upstream_admission']['linked_sha256']+'`.', '',
                '| Requested backend | Frame | Call | Dimensions | RGBA SHA256 |',
                '|---|---:|---:|---|---|']
            for row in report['runs']:
                for frame in row.get('observed', {}).get('frames', []):
                    lines.append(f"| {row['backend']} | {frame['index']} | {frame['call']} | {frame['width']}×{frame['height']} | `{frame['rgba_sha256']}` |")
        lines += ['', 'First mismatch: '+report.get('error', 'none observed')]
        if report.get('error'):
            lines += ['', 'First failure: '+report['error']]
        lines += ['', 'Exact source/input/compiler/image identities and per-frame RGBA SHA256 receipts: results.json.',
                  'A one-call pilot does not qualify the continuing two-call CI sequence.']
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')

    def command(args, name, environment=None, required=True):
        """A failed child never becomes a skipped backend or stale receipt; preserve bounded origin diagnostics."""
        row = checks.command(args, name, environment=environment, timeout=1800)
        if required and row['exit_code']:
            raise RuntimeError(name+' failed: '+row['output'][-2000:])
        return row

    save()
    try:
        report['host'] = host_identity()
        report['revision'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip()
        report['toolchain'] = json.loads((ROOT/'spec/toolchain.json').read_text())
        report['polkavm'] = json.loads((ROOT/'spec/polkavm-pins.json').read_text())
        report['assets'] = json.loads((ROOT/'spec/pvm-doom-assets.json').read_text())
        # Maintained preparation validates pristine pinned sources, complete oracle state and upstream frame1320.
        prepare_doom(check_only=True, warmup=1320)
        admission = json.loads((DOOM/'results.json').read_text())
        if admission['status'] != 'checks-passed' or not admission.get('golden_rgba_sha256'):
            raise ValueError('missing complete upstream DOOM golden admission')
        report['upstream_admission'] = admission
        library = build_native()
        compiler, _ = installed()
        sources = [*sorted((ROOT/'src').rglob('*.nim')), *sorted((ROOT/'native/pvm_jit').glob('*')),
                   *sorted((ROOT/'native/polkavm').rglob('*')), *sorted((ROOT/'tools').glob('*.py')),
                   DRIVER, ROOT/'Makefile', ROOT/'.github/workflows/ci.yml',
                   DOOM/'doom.polkavm', ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad',
                   ROOT/'spec/toolchain.json', ROOT/'spec/polkavm-pins.json',
                   ROOT/'spec/pvm-doom-assets.json', compiler, library,
                   *sorted((DOOM/'prepared').glob('*'))]
        identities = {p:digest(p) for p in sources if p.is_file()}
        report['identities'] = {str(p.relative_to(ROOT)):h for p,h in identities.items()}
        pages = int.from_bytes((DOOM/'prepared/tick.input').read_bytes()[16:20], 'little')
        if not 0 < pages <= 8192:
            raise ValueError('unbounded DOOM initial snapshot')
        flags = ['pvmArm64Jit', 'polkavmRuntime']
        cflags = ['-I'+str(ROOT/'native/pvm_jit'), '-I'+str(ROOT/'native/polkavm')]
        built, binary = checks.build(compiler, DRIVER, 'doom-backends', defines=flags, cflags=cflags,
                                    link_flags=[str(library), '-Wl,-rpath,'+str(library.parent)])
        report['builds'].append(built)
        if built['exit_code']: raise RuntimeError(built['output'][-2000:])
        identities[binary] = digest(binary)
        observed = {}
        common = dict(os.environ, RAGNAROK_DOOM_BACKEND_OUTPUT=str(BUILD),
            RAGNAROK_PVM_DOOM_INPUT=str(DOOM/'prepared'),
            RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'),
            RAGNAROK_DOOM_BACKEND_CALLS=str(count), RAGNAROK_DOOM_BACKEND_ASSERT='0')
        for selected in BACKENDS:
            # One process per real CLI selection owns its initial restore and all continuing guest state.
            folder = BUILD/selected
            folder.mkdir(exist_ok=True)
            env = dict(common, RAGNAROK_DOOM_BACKEND_OUTPUT=str(folder))
            unchanged(identities)
            row = command([binary, '--pvm-backend', selected], selected, env)
            item = observation(row['output'], folder, selected, count, pages, report['host']['architecture'])
            observed[selected] = item
            report['runs'].append(dict(backend=selected, run=row, observed=item))
            save()
        reference, candidate = (observed[name] for name in BACKENDS)
        compare(reference, candidate, count)
        if reference['frames'][0]['rgba_sha256'] != admission['golden_rgba_sha256']:
            raise Mismatch('frame 0: pinned upstream RGBA golden mismatch')
        # Rehash changed bytes from the actual candidate framebuffer; never mutate an expected/golden hash.
        data = bytearray((BUILD/'jit/call-0.events').read_bytes())
        at = 0
        while data[at] != 1:
            at += 5+int.from_bytes(data[at+1:at+5], 'little')
        data[at+5+8] ^= 1
        changed_frames = rgba_frames(bytes(data), 0, 0)
        changed = changed_frames+candidate['frames'][len(changed_frames):]
        report['controls'] += negative_frames(reference, candidate, count, changed)
        for name, args, env, needle in (
            ('assertions', [binary,'--pvm-backend','jit'], dict(common, RAGNAROK_DOOM_BACKEND_ASSERT='1'), 'DOOM backend assertion control'),
            ('wrong-backend', [binary,'--pvm-backend','interpreted'], common, 'unsupported DOOM comparison backend')):
            row = command(args, name, env, required=False)
            if row['exit_code'] == 0 or needle not in row['output']:
                raise ValueError('missing intended process refusal: '+name)
            report['controls'].append(dict(control=name, refused=True, run=row))
        # A genuinely unlinked image must expose BackendNotBuilt instead of silently running ours.
        built, absent = checks.build(compiler, DRIVER, 'doom-no-bridge', defines=['pvmArm64Jit'], cflags=cflags)
        report['builds'].append(built)
        if built['exit_code']: raise RuntimeError(built['output'][-2000:])
        identities[absent] = digest(absent)
        row = command([absent,'--pvm-backend','polkavm-interpreted'], 'unavailable-bridge', common, required=False)
        if row['exit_code'] == 0 or 'DOOM_BACKEND_UNAVAILABLE,polkavm-interpreted,BackendNotBuilt' not in row['output']:
            raise ValueError('unavailable bridge did not refuse explicitly')
        report['controls'].append(dict(control='unavailable-bridge', refused=True, run=row))
        unchanged(identities)
        report['identities'] = {str(p.relative_to(ROOT)):h for p,h in identities.items()}
        report['frames_compared'] = len(reference['frames'])
        report['status'] = 'passed' if count == 2 else 'pilot-passed'
    except BaseException as error:
        report['error'] = str(error)
        raise
    finally:
        save()


if __name__ == '__main__':
    run()
