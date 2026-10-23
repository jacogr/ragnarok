# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared strict admission for resource counters, checked native commands and interpreter/source provenance."""
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import platform
import re
import sys
from storage_benchmark import benchmark_sources

ROOT = Path(__file__).resolve().parents[1]


def digest(value, length=64):
    """An identity has one canonical bounded hexadecimal representation; it grants no execution authority."""
    return type(value) is str and re.fullmatch('[0-9a-f]{'+str(length)+'}', value) is not None


def python_identity():
    """Freeze the observer interpreter separately from the native workload's checked build identity."""
    return dict(executable=sys.executable, version=platform.python_version(),
                sha256=hashlib.sha256(Path(sys.executable).read_bytes()).hexdigest())


def validate_python(value):
    """Imported reports describe an interpreter; validators never execute or open its supplied path."""
    if (type(value) is not dict or set(value) != {'executable', 'version', 'sha256'} or
            any(type(value[k]) is not str or not 0 < len(value[k]) <= 4096 or '\x00' in value[k] for k in ('executable','version')) or
            not digest(value['sha256'])):
        raise ValueError('Invalid resource observer interpreter identity')
    return value


def validate_counters(value):
    """Whole-child observations reject boolean aliases, unavailable RSS and negative/overflowing fault counts."""
    if (type(value) is not dict or set(value) != {'peak_rss_bytes','minor_faults','major_faults'} or
            any(type(v) is not int or not 0 <= v < 1<<63 for v in value.values()) or value['peak_rss_bytes'] == 0):
        raise ValueError('Invalid resource child counters')
    return value


def validate_checks(checks, count):
    """Each source-owned build/run requires its own successful finite receipt and exact bounded argument vector."""
    if type(checks) is not list or len(checks) != count:
        raise ValueError('Incomplete resource execution coverage')
    logs = []
    for check in checks:
        if type(check) is not dict or type(check.get('exit_code')) is not int or check['exit_code'] != 0:
            raise ValueError('Failed resource execution')
        elapsed = check.get('elapsed_seconds'); command = check.get('command'); log = check.get('log')
        if (type(elapsed) not in (int,float) or not math.isfinite(elapsed) or not 0 <= elapsed <= 86400 or
                type(log) is not str or not 0 < len(log) <= 4096 or type(command) is not list or not 0 < len(command) <= 128 or
                any(type(v) is not str or not 0 < len(v) <= 4096 or '\x00' in v for v in command)):
            raise ValueError('Invalid resource execution receipt')
        logs.append(log)
    if len(set(logs)) != len(logs):
        raise ValueError('Duplicate resource execution logs')
    return checks


def validate_build(check, source, defines):
    """Native resource builds admit only the maintained checked ARC/Clang/LTO crypto profile."""
    build = check['command']; required = ['--mm:arc','--cc:clang','-d:release','--opt:speed','--boundchecks:on',
                                         '--passC:-flto=thin','--passL:-flto=thin']
    crypto = ROOT/'build/crypto'; include = '--passC:-I'+str(ROOT/'native/crypto')
    libraries = {'--passL:'+str(crypto/'libragnarok_crypto.dylib'), '--passL:'+str(crypto/'libragnarok_crypto.so')}
    rpath = '--passL:-Wl,-rpath,'+str(crypto)
    if len(build) < 14 or build[1] != 'c' or build[2:9] != required or build[-1] != str(source):
        raise ValueError('Invalid checked resource build')
    flags = build[2:-1]; outputs = [v[6:] for v in flags if v.startswith('--out:')]
    if len(outputs) != 1 or len([v for v in flags if v.startswith('--nimcache:')]) != 1:
        raise ValueError('Ambiguous resource build output/cache')
    expected = [*required, include, rpath, *['-d:'+d for d in defines]]
    if any(flags.count(v) != 1 for v in expected) or len(libraries.intersection(flags)) != 1:
        raise ValueError('Missing resource build input flags')
    allowed = set(expected) | libraries | {'--passL:-fuse-ld=lld'}
    if any(v not in allowed and not v.startswith(('--out:','--nimcache:')) for v in flags):
        raise ValueError('Unchecked or undeclared resource build flag')
    return outputs[0]


def validate_inputs(value, source):
    """Require the complete storage helper/runtime inventory and canonical compiler/provider/source identities."""
    if (type(value) is not dict or not digest(value.get('head'),40) or type(value.get('dirty')) is not bool or
            not digest(value.get('compiler_sha256')) or type(value.get('clang')) is not str or not value['clang'] or
            value.get('toolchain') != json.loads((ROOT/'spec/toolchain.json').read_text())):
        raise ValueError('Invalid resource source/toolchain provenance')
    sources = value.get('sources')
    required = [*benchmark_sources(), source, *sorted((ROOT/'tools').glob('storage_*.py')),
                *sorted((ROOT/'tests/support').glob('storage_*.nim'))]
    if type(sources) is not dict or not {str(p.relative_to(ROOT)) for p in required} <= set(sources):
        raise ValueError('Incomplete resource source closure')
    for name, identity in sources.items():
        path = PurePosixPath(name)
        if type(name) is not str or path.is_absolute() or '..' in path.parts or str(path) != name or not digest(identity):
            raise ValueError('Invalid resource source identity')
    components = value.get('native_components')
    if (type(components) is not dict or set(components) != {'bridge','provider_loader','provider_build'} or
            any(not digest(v) for v in components.values()) or components['provider_loader'] != components['provider_build']):
        raise ValueError('Invalid resource native provider closure')
    validate_python(value.get('python_identity'))
    return value
