# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""One native checked-read leaf gate with an independent full assembly fixture."""
from hashlib import sha256
from pathlib import Path
import json
import os
import re
import shutil
import signal
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/x86-checked-read-direct'
OUT = BUILD / 'evidence'
BASE = '621bccb293cb53d2bca53184dbe4dfb1d41dfb5f'
COMMON = '5db0de9c315bc4353810a3a997af536f9e1741f8'
PORT = '370ebb820f8b6f15cd215ddaa2ab1fac1aa140b5'
REF = 'refs/heads/codex/pvm-x86-read-native-qualification-version-gate'
WORKFLOW = '.github/workflows/polkavm-ratios.yml'
GOLDEN = '.github/qualification/x86-checked-read-golden.s'
CARRIER = '.github/qualification/x86-checked-read.py'
SPEC_SHA = 'b71b3f88f06f8022fa1d60082948e90cd9cc22833e53cc11d35f9be6692248ff'
COMPILER_SHA = '8abde75413136cf04572e06254f84a27b43ec5903ad105123e5b6e630cacc78f'
ARCHIVE_SHA = '2425e2dca6e4b13fb2b4149b75e0f445feb61702caab02960df91cf085723a3c'
WITNESS = ROOT / 'tests/performance/pvm_checked_read_body_witness.nim'
DUMP = 'RAGNAROK_PVM_CHECKED_READ_BODY_DUMP'
MAX_LEAF = 4096


def digest(path):
    """Hash exact local bytes, including failed process output."""
    return sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    """Stop the gate with a concrete first failure."""
    if not condition:
        raise ValueError(message)


def save(name, value):
    """Retain evidence atomically for the always-run artifact step."""
    path = OUT / name
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def run(name, args, timeout=10, env=None, output=None):
    """Bound and reap the entire process group and preserve its status before checking it."""
    argv = [str(arg) for arg in args]
    stdout = OUT / (output or name + '.stdout')
    stderr = OUT / (name + '.stderr')
    record = dict(argv=argv, timeout_seconds=timeout, stdout=stdout.name, stderr=stderr.name,
                  exit_code=None, timed_out=False)
    save(name + '.json', record)
    with stdout.open('xb') as log, stderr.open('xb') as errors:
        with subprocess.Popen(argv, cwd=ROOT, env=env, stdout=log, stderr=errors,
                              start_new_session=True) as process:
            try:
                record['exit_code'] = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    # The process may exit between the timeout and the signal.
                    pass
                process.wait()
                record.update(exit_code=124, timed_out=True)
    record.update(stdout_sha256=digest(stdout), stderr_sha256=digest(stderr))
    save(name + '.json', record)
    require(record['exit_code'] == 0, name + ' exited ' + str(record['exit_code']))
    return stdout


def git(*args, env=None):
    """Read exact local Git identities or update the isolated projection index."""
    return subprocess.check_output(['git', *args], cwd=ROOT, env=env,
                                   text=True, timeout=10).strip()


def bind_source():
    """Project the carrier commit onto the sealed source by removing only carrier files."""
    head = git('rev-parse', 'HEAD')
    require(os.environ.get('GITHUB_REF') == REF, 'wrong qualification ref')
    require(os.environ.get('GITHUB_EVENT_NAME') == 'workflow_dispatch', 'manual dispatch required')
    require(os.environ.get('GITHUB_RUN_ATTEMPT') == '1', 'first attempt required')
    require(os.environ.get('GITHUB_SHA') == head, 'checkout and dispatched head disagree')
    require(git('show', '-s', '--format=%P', head) == BASE, 'wrong carrier parent')
    require(not git('status', '--porcelain', '--untracked-files=no'), 'tracked source is dirty')
    index = dict(os.environ, GIT_INDEX_FILE=str(BUILD / 'projected.index'))
    git('read-tree', head, env=index)
    git('update-index', '--force-remove', '--', GOLDEN, CARRIER, env=index)
    mode, kind, blob, filename = git('ls-tree', BASE, '--', WORKFLOW).split(maxsplit=3)
    require(kind == 'blob' and filename == WORKFLOW, 'wrong original workflow object')
    git('update-index', '--cacheinfo', mode + ',' + blob + ',' + WORKFLOW, env=index)
    require(git('write-tree', env=index) == PORT, 'sealed source tree disagrees')
    require(digest(ROOT / 'spec/toolchain.json') == SPEC_SHA, 'wrong toolchain manifest')
    save('SOURCE.json', dict(base=BASE, common=COMMON, head=head, port=PORT, ref=REF,
         files={name: digest(ROOT / name) for name in (WORKFLOW, GOLDEN, CARRIER)}))


def check_layout(layout):
    """Require all three generated C layouts and the exact descriptor field offsets."""
    blocks = layout.split('*** Dumping AST Record Layout')
    expected = (
        (r'\|\s+NU64\[13\]\s+a\b', 104),
        (r'\|\s+NativeReadRegion_\w+\[3\]\s+a\b', 72),
        (r'0\s+\|\s+struct NativeReadRegion_\w+\b', 24),
    )
    for pattern, width in expected:
        matches = [block for block in blocks if re.search(pattern, block)]
        require(len(matches) == 1 and f'[sizeof={width}, align=8]' in matches[0],
                'unexpected generated C layout for ' + str(width) + ' bytes')
    region = next(block for block in blocks if re.search(expected[2][0], block))
    for offset, field in ((0, 'first'), (8, 'length'), (16, 'data')):
        require(re.search(r'(?m)^\s*'+str(offset)+r'\s+\|[^\n]*\b'+field+r'_\d+\s*$', region),
                'wrong descriptor offset for ' + field)


def audit_link(binary, cache):
    """Bind generated borrow argument order, linked SysV transfer and C layout."""
    run('elf-header', ['readelf', '-h', binary])
    with binary.open('rb') as stream:
        header = stream.read(20)
    require(len(header) == 20 and header[:6] == b'\x7fELF\x02\x01'
            and struct.unpack_from('<H', header, 18)[0] == 62,
            'linked witness is not a little-endian amd64 ELF64')
    units = [path for path in cache.glob('c/*/*.c')
             if 'pvm_x86_arena_region(' in path.read_text()
             and 'enterNativeReadBody_' in path.read_text()]
    require(len(units) == 1, 'missing unique generated wrapper')
    wrapper = units[0]
    shutil.copyfile(wrapper, OUT / 'linked-wrapper.c')
    call = re.findall(r'pvm_x86_arena_region\(([^\n;]*)\);', wrapper.read_text())
    require(len(call) == 1 and re.search(r'registers_\d+.*context_\d+', call[0]),
            'generated wrapper does not pass register then context borrows')
    layout = run('clang-layout', ['clang', '-fsyntax-only', '-I'+str(ROOT/'native/pvm_jit'),
                 '-Xclang', '-fdump-record-layouts-complete', wrapper], 30).read_text()
    check_layout(layout)
    symbols = run('linked-symbols', ['nm', '--defined-only', binary]).read_text()
    names = re.findall(r'(?m)^[0-9a-f]+\s+[tT]\s+(enterNativeReadBody_\w+)$', symbols)
    require(len(names) == 1, 'missing unique linked read entry')
    wrapper_disasm = run('linked-sysv', ['objdump', '-d', '-Mintel',
                        '--disassemble='+names[0], binary], 15).read_text()
    transfers = [line for line in wrapper_disasm.splitlines()
                 if re.search(r'\bcall\s+r(?:ax|bx|cx|dx|si|di|8|9|10|11|12|13|14|15)\s*$', line)]
    require(len(transfers) == 1 and re.search(
            r'\bmov\s+rdi,\s*rsi[^\n]*\n[^\n]*\bmov\s+rsi,\s*rdx[^\n]*\n[^\n]*\bcall\s+r\w+\s*$',
            wrapper_disasm, re.MULTILINE),
            'linked register/context transfer differs from reviewed SysV form')
    save('ABI.json', dict(register_bytes=104, context_bytes=72, descriptor_bytes=24,
                          field_offsets=[0,8,16], linked_symbol=names[0],
                          transfer=transfers[0].strip(), elf_sha256=digest(binary)))


def main():
    """Run each phase once and permit executable entry only after full byte comparison."""
    OUT.mkdir(parents=True, exist_ok=False)
    stage = 'source'
    save('RESULT.json', dict(status='running'))
    try:
        bind_source()
        stage = 'host'
        uname = run('host', ['uname', '-sm']).read_text().strip()
        require(uname == 'Linux x86_64' and os.environ.get('RUNNER_ARCH') == 'X64',
                'native Linux x86-64 required')
        require(not Path('/.dockerenv').exists() and not Path('/run/.containerenv').exists(),
                'native runner required')
        stage = 'host-tools'
        run('host-tools', ['make', 'host-tools'], 120)
        stage = 'host'
        tools = {}
        for tool in ('make', 'clang', 'ld.lld', 'as', 'objcopy', 'objdump', 'readelf', 'nm'):
            path = shutil.which(tool)
            require(path, 'missing host tool ' + tool)
            resolved = Path(path).resolve()
            tools[tool] = dict(path=str(resolved), sha256=digest(resolved))
        save('HOST-TOOLS.json', tools)
        run('clang-version', ['clang', '--version'])
        run('lld-version', ['ld.lld', '--version'])
        run('assembler-version', ['as', '--version'])
        run('objdump-version', ['objdump', '--version'])
        stage = 'toolchain'
        run('compiler-tools', ['make', 'compiler-tools'], 150)
        manifest = json.loads((ROOT/'build/toolchain/environment.json').read_text())
        compiler = Path(manifest['compiler'])
        require(manifest['pins_sha256'] == SPEC_SHA and digest(compiler) == COMPILER_SHA,
                'wrong installed compiler')
        archive = ROOT/'build/toolchain'/('nimony-'+ARCHIVE_SHA+'.archive')
        require(digest(archive) == ARCHIVE_SHA, 'wrong Linux toolchain archive')
        run('compiler-version', [compiler, '--version'])
        version = (OUT / 'compiler-version.stderr').read_text().strip()
        require(version == '0.6.3 [linux; amd64]', 'wrong compiler profile')
        save('TOOLCHAIN.json', dict(archive_sha256=ARCHIVE_SHA, compiler_sha256=COMPILER_SHA,
                                   spec_sha256=SPEC_SHA, version=version.strip()))
        stage = 'link'
        env = {key: value for key, value in os.environ.items() if not key.startswith('RAGNAROK_PVM_')}
        env['PATH'] = str(compiler.parent) + ':' + env['PATH']
        cache = BUILD/'cache'
        binary = OUT/'direct.elf'
        run('link', [compiler, 'c', '--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
            '--boundchecks:on', '--passC:-flto=thin', '--passL:-flto=thin', '--passL:-fuse-ld=lld',
            '-d:pvmX86Jit', '-d:pvmX86CheckedRead', '--passC:-I'+str(ROOT/'native/pvm_jit'),
            '--nimcache:'+str(cache), '--out:'+str(binary), WITNESS], 120, env)
        elf_sha = digest(binary)
        stage = 'linked-abi'
        audit_link(binary, cache)
        stage = 'independent-golden'
        obj = BUILD/'golden.o'
        golden = OUT/'GOLDEN.bin'
        run('golden-assemble', ['as', '--64', '-o', obj, ROOT/GOLDEN], 15)
        run('golden-extract', ['objcopy', '-O', 'binary', '--only-section=.text', obj, golden], 15)
        require(golden.stat().st_size == 509, 'reviewed golden has an unexpected extent')
        stage = 'emitted-byte-dump'
        leaf = run('dump', [binary], 45, dict(env, **{DUMP:'1'}), 'LEAF.bin')
        require(0 < leaf.stat().st_size <= MAX_LEAF, 'emitted leaf exceeds the bounded extent')
        run('leaf-disassembly', ['objdump', '-D', '-b', 'binary', '-m', 'i386:x86-64',
                                 '-Mintel', leaf], 15, output='LEAF.disasm')
        stage = 'full-byte-gate'
        require(leaf.read_bytes() == golden.read_bytes(), 'complete emitted fixture differs from assembler golden')
        require(digest(binary) == elf_sha, 'linked image changed before direct entry')
        save('BYTE-GATE.json', dict(leaf_bytes=leaf.stat().st_size, leaf_sha256=digest(leaf),
             golden_sha256=digest(golden), elf_sha256=elf_sha, equal=True))
        stage = 'direct-success-and-refusal'
        direct = run('direct', [binary], 45, env)
        require(direct.read_bytes() == b'PVM_CHECKED_READ_BODY_OK\n', 'wrong direct witness output')
        require((OUT/'direct.stderr').stat().st_size == 0, 'unexpected direct witness diagnostic')
        require(digest(binary) == elf_sha, 'linked image changed during direct entry')
        save('RESULT.json', dict(status='passed', leaf_sha256=digest(leaf), elf_sha256=elf_sha,
                                 success_and_late_refusal=True))
    except Exception as error:
        save('FIRST-FAILURE.json', dict(stage=stage, error=repr(error)))
        save('RESULT.json', dict(status='failed', stage=stage))
        raise


if __name__ == '__main__':
    main()
