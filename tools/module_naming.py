# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Check production import aliases and area-qualified native test filenames without compiling.

Source directories own production namespaces; filenames remain unchanged. Ordinary and selective
imports bind modules; textual includes introduce no module binding and need no alias.
"""
from pathlib import Path
import re
from nim_dependencies import import_text


# Keep nested/internal source modules in their top-level owner's namespace.
def module_alias(module, source_root):
    """Return the canonical area_type binding for an existing production module."""
    relative = module.relative_to(source_root)
    area = relative.parts[0] if len(relative.parts) > 1 else 'ragnarok'
    return module.stem if module.stem.startswith(area+'_') else area+'_'+module.stem


# Match the project's source-relative/root-relative import search without consulting generated trees.
def production_module(source, name, root):
    """Resolve an owned source import; return None for stdlib, test helpers and external modules."""
    if name.startswith('std/'):
        return None
    name = name if name.endswith('.nim') else name+'.nim'
    for candidate in (source.parent/name, root/name, root/'src'/name):
        candidate = candidate.resolve()
        if candidate.is_relative_to(root/'src') and candidate.is_file():
            return candidate
    return None


# Expand groups before splitting imports so direct, grouped and multiline declarations share checks.
def module_imports(text):
    """Yield (path, alias) pairs from import declarations, ignoring comments and fixture strings."""
    lines = import_text(text).splitlines()
    index = 0
    while index < len(lines):
        match = re.match(r'^\s*(import|from)\s+(.+)', lines[index])
        index += 1
        if match is None:
            continue
        body = match[2].strip()
        while index < len(lines) and (body.count('[') > body.count(']') or body.endswith(',')):
            body += ' '+lines[index].strip()
            index += 1
        body = re.split(r'\s+'+('import' if match[1] == 'from' else 'except')+r'\s+', body, maxsplit=1)[0]
        body = re.sub(r'([\w./-]+/)\[([^\]]+)\]',
                      lambda m: ','.join(m[1]+part.strip() for part in m[2].split(',')), body)
        for part in body.split(','):
            value = re.fullmatch(r'\s*("[^"\n]+"|[\w./-]+)(?:\s+as\s+(\w+))?\s*', part)
            if value is None:
                raise ValueError('Unsupported module import declaration: '+part)
            yield value[1].strip('"'), value[2]


# Run in inventory preflight so new areas and consumers cannot silently restore generic bindings.
def validate_module_names(root):
    """Reject generic/wrong-area production aliases and unqualified native test filenames."""
    root = Path(root).resolve()
    source_root = root/'src'
    modules = sorted(source_root.rglob('*.nim'))
    if not modules:
        raise ValueError('No production Nim modules for naming validation')
    areas = {p.relative_to(source_root).parts[0] for p in modules
             if len(p.relative_to(source_root).parts) > 1}
    areas.update(('ragnarok', 'nimony', 'compiler', 'testing'))
    tests = sorted((root/'tests').rglob('*.nim'))
    for source in modules+tests:
        # Standard library/test-only imports retain their existing namespaces.
        for name, alias in module_imports(source.read_text()):
            module = production_module(source, name, root)
            if module is not None:
                expected = module_alias(module, source_root)
                if (alias or module.stem) != expected:
                    raise ValueError(str(source.relative_to(root))+': import '+name+' as '+expected)
    for source in tests:
        # Test filenames also become global suite/module identities in otherwise flat inventories.
        name = source.stem.removeprefix('test_')
        if not any(name.startswith(area+'_') for area in areas):
            raise ValueError('Native test must use [test_]<area>_<type>.nim: '+str(source.relative_to(root)))
    return len(modules), len(tests)
