"""Shared Nim build and fixture-runner helpers; production protocol code lives under src/."""
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]


# Build checked ARC binaries with Clang; optimized builds use LTO without disabling runtime guards.
def nim_command(source, output, cache, libraries=()):
    return ['nim', 'c', '--mm:arc', '--cc:clang', '--clang.linkerexe:clang++',
            '--skipParentCfg', '--skipUserCfg', '-d:release', '--opt:speed', '--passC:-O3',
            '--passC:-flto', '--passL:-flto',
            *(['--passL:-fuse-ld=lld'] if platform.system() == 'Linux' else []),
            '--assertions:on', '--boundChecks:on', '--rangeChecks:on', '--fieldChecks:on',
            '--overflowChecks:on', *[f'--passL:{library}' for library in libraries],
            f'--nimcache:{cache}', f'--out:{output}', str(source)]


# Batch codec runners take one request file; every supplied path must be an existing native binary.
def codec_commands(build, paths, mode):
    return [[str(path)] for path in paths]


# Networking workloads use the one Nim peer and its one-thread dispatcher baseline.
def networking_peers(build, skip_build, thread_baselines, variant=None):
    assert (build/'nim-peer').is_file(), 'Build the native peer before running this workload'
    thread_baselines['nim'] = 1
    return ('nim',)


# Deliberate nominal-domain probes must fail for their intended reason, not a missing import/tool.
def reject_types(cases, folder):
    folder.mkdir(parents=True, exist_ok=True)
    records = []
    # Keep each misuse separate so the first error cannot conceal another accepted invalid program.
    for name, source, needles in cases:
        command = ['nim', 'check', '--mm:arc', '--skipParentCfg', '--skipUserCfg', str(source)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
        text = result.stdout+result.stderr
        path = folder/f'{name}.log';path.write_text(text)
        assert result.returncode != 0 and 'type mismatch' in text, (name, text)
        assert all(needle in text for needle in needles), (name, text)
        records.append(dict(case=name, command=command, status='rejected', log=str(path.relative_to(ROOT))))
    return records
