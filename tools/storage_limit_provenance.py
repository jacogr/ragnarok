# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Freeze checked storage inputs, actual interpreter, native executable and observed host identities."""
import hashlib
from pathlib import Path
import platform
from storage_resource_panel import panel_identity
from storage_resource_validation import validate_inputs,digest
from storage_benchmark import cpu_model

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'tests/performance/storage_fresh_reopen.nim'


def identity(compiler,library,binary):
    """Include the full storage helper closure; no imported report path is ever executed by validation."""
    return dict(inputs=panel_identity(compiler,library,SOURCE),native_binary_sha256=hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
                host=dict(system=platform.system(),platform=platform.platform(),machine=platform.machine(),cpu=cpu_model()))


def validate_identity(value):
    """A bounded report carries exact native/compiler/interpreter inputs and a supported host."""
    if type(value) is not dict or set(value)!= {'inputs','native_binary_sha256','host'} or not digest(value['native_binary_sha256']):
        raise ValueError('Invalid memory experiment binary identity')
    validate_inputs(value['inputs'],SOURCE)
    host=value['host']
    if type(host) is not dict or set(host)!= {'system','platform','machine','cpu'} or host['system'] not in ('Linux','Darwin') or any(type(v) is not str or not 0<len(v)<=4096 for v in host.values()):
        raise ValueError('Invalid memory experiment host identity')
    return value
