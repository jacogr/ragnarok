# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Derive compatible build units and generate small module-isolated Contract dispatchers.

A bundle is opt-in family metadata, not a second suite registry. Probe argv and module scopes
remain independent; generated dispatchers append only a routing argument to each child command.
"""
import json
import os
from pathlib import Path
from native_checks import ROOT


# Every grouped family must use exactly the same ABI, feature flags and checked compilation profile.
def profile(suite):
    """Return an immutable compatibility identity including ordered native libraries and defines."""
    return (str(Path(suite['source']).parent), suite.get('crypto_library'), suite.get('quic_library'),
            tuple(suite.get('native_libraries', ())), tuple(suite.get('defines', ())))


def build_units(suites):
    """Group only declared compatible families; ordinary families retain singleton ownership."""
    units = {}
    for name, suite in suites.items():
        key = ('bundle', suite['bundle']) if suite.get('bundle') else ('family', name)
        members = units.setdefault(key, [])
        if members and profile(suites[members[0]]) != profile(suite):
            raise ValueError('Incompatible Contract bundle: '+str(key))
        members.append(name)
    return units


def bundle_source(folder, name, members, suites):
    """Generate one runtime dispatcher; each imported fixture exposes runFailureProbe(selection)."""
    folder = Path(folder)/'bundles'
    folder.mkdir(parents=True, exist_ok=True)
    source = folder/(name.replace('-', '_')+'.nim')
    lines = ['# Copyright (c) 2026 Ragnarök contributors',
             '# SPDX-License-Identifier: MIT OR Apache-2.0',
             '## Generated Contract dispatcher; each invocation selects exactly one family.',
             'import std/[cmdline, syncio]']
    for index, family in enumerate(members):
        relative = os.path.relpath(ROOT/suites[family]['source'], folder).removesuffix('.nim')
        lines.append('import '+json.dumps(relative)+' as fixture'+str(index))
    lines += ['let family = paramStr(paramCount())', 'case family']
    for index, family in enumerate(members):
        lines += ['of '+json.dumps(family)+':', '  fixture'+str(index)+'.runFailureProbe(paramStr(1))']
    lines += ['else:', '  quit 2 # Unknown routing is a setup failure, never a tested rejection.']
    source.write_text('\n'.join(lines)+'\n')
    return source
