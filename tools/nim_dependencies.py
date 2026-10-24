# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Estimate Nim test cost from unique reachable project modules, without invoking a compiler.

transitive_dependencies reads import/from/include declarations, grouped paths and aliases. It
includes all conditional branches as a scheduling heuristic, not a compiler dependency manifest.
Standard-library, generated and external sources are excluded; this never selects test coverage.
"""
from functools import lru_cache
from pathlib import Path
import re


# Remove comments and multiline string fixtures while preserving declaration boundaries and quoted paths.
def import_text(text):
    tokens = re.compile(r'#\[|\]#|"""|"(?:\\.|[^"\\\n])*"|#[^\n]*')
    result = []
    offset = 0
    depth = 0
    quoted = False
    while offset < len(text):
        # Only nesting delimiters matter inside comments; only the closing delimiter matters in strings.
        pattern = re.compile(r'#\[|\]#') if depth else re.compile('"""') if quoted else tokens
        match = pattern.search(text, offset)
        end = match.start() if match else len(text)
        hidden = depth or quoted
        prefix = text[offset:end]
        result.append(''.join('\n' if c == '\n' else ' ' for c in prefix) if hidden else prefix)
        if match is None:
            break
        token = match.group()
        if depth:
            depth += 1 if token == '#[' else -1
        elif quoted:
            quoted = False
        elif token == '#[':
            depth = 1
        elif token == '"""':
            quoted = True
        elif token.startswith('"'):
            # Ordinary strings can contain comment markers; keep them intact for quoted import paths.
            result.append(token)
            offset = match.end()
            continue
        result.append(''.join('\n' if c == '\n' else ' ' for c in token))
        offset = match.end()
    return ''.join(result)


# Read source-owned module references, expanding grouped imports before separating ordinary paths.
def imported_modules(text):
    lines = import_text(text).splitlines()
    names = set()
    index = 0
    while index < len(lines):
        declaration = re.match(r'^\s*(import|from|include)\s+(.+)', lines[index])
        index += 1
        if declaration is None:
            # Non-declarations do not participate in the cost estimate.
            continue
        kind, body = declaration.groups()
        body = body.strip()
        while index < len(lines) and (body.count('[') > body.count(']') or body.endswith(',')):
            # Grouped paths and comma continuations may span multiple source lines.
            body += ' '+lines[index].strip()
            index += 1
        if kind == 'from':
            body = re.split(r'\s+import\s+', body, maxsplit=1)[0]
        else:
            body = re.split(r'\s+except\s+', body, maxsplit=1)[0]
        body = re.sub(r'([\w./]+/)\[([^\]]+)\]',
                      lambda match: ','.join(match[1]+part.strip() for part in match[2].split(',')), body)
        for part in body.split(','):
            # Aliases affect identifiers, not module identity; sets remove repeated imports.
            name = re.split(r'\s+as\s+', part.strip(), maxsplit=1)[0].strip().strip('"')
            if name:
                names.add(name)
    return names


# Share parsed edges across roots and terminate cycles; count every reachable project source once per root.
def transitive_dependencies(sources, root):
    root = Path(root).resolve()
    owned = (root/'src', root/'tests')

    @lru_cache(maxsize=None)
    def direct(source):
        """Read one module once and resolve only existing project-owned module paths."""
        dependencies = set()
        for name in imported_modules(source.read_text()):
            if name.startswith('std/'):
                # The pinned standard library is not needed to reproduce this source-only heuristic.
                continue
            relative = Path(name if name.endswith('.nim') else name+'.nim')
            for candidate in (source.parent/relative, root/relative, root/'src'/relative):
                # Generated build inputs, external packages and unresolved names have no project weight.
                candidate = candidate.resolve()
                if any(candidate.is_relative_to(base) for base in owned) and candidate.is_file():
                    dependencies.add(candidate)
                    break
        return dependencies

    result = {}
    for source in sources:
        # The root itself is not an imported module, even when a dependency cycle returns to it.
        source = Path(source).resolve()
        seen = {source}
        pending = list(direct(source))
        while pending:
            dependency = pending.pop()
            if dependency not in seen:
                seen.add(dependency)
                pending.extend(direct(dependency))
        result[source] = frozenset(seen-{source})
    return result
