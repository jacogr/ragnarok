# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Normalize Nim section spacing without rewriting literal or block-comment contents."""
import re

ROUTINE = re.compile(r'^(?:proc|func|method|iterator|template|macro|converter)\s')
CHARACTER = re.compile(r"'(?:\\(?:[0-9]+|x[0-9a-fA-F]{2}|.)|[^'\\\n])'")


def source_lines(source):
    """Yield each line, its code-only mask and whether it starts inside a multiline token."""
    triple = False
    comments = 0
    comment_open = '#['
    comment_close = ']#'
    # Keep state across lines so embedded snippets never become formatting instructions.
    # Nim recognizes CR/LF boundaries; Unicode separators remain literal UTF-8 contents.
    for line in re.findall(r'[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+$', source):
        protected = triple or comments > 0
        mask = [' '] * len(line)
        index = 0
        # Only code outside comments and literals may identify a declaration boundary.
        while index < len(line):
            if comments:
                # Nested delimiters follow the outer comment's mode, including overlapping markers.
                if line.startswith(comment_open, index):
                    comments += 1
                    index += 1
                elif line.startswith(comment_close, index):
                    comments -= 1
                    index += len(comment_close) if comments == 0 else 1
                else:
                    index += 1
            elif triple:
                # Nim closes at the last three quotes of a run; preceding quotes are literal content.
                if line.startswith('"""', index) and not line.startswith('""""', index):
                    triple = False
                    index += 3
                else:
                    index += 1
            elif line.startswith(('##[', '#['), index):
                comments = 1
                # Documentation comments treat plain ]# and #[ as text; ordinary comments do not.
                documentation = line.startswith('##[', index)
                comment_open = '##[' if documentation else '#['
                comment_close = ']##' if documentation else ']#'
                index += len(comment_open)
            elif line[index] == '#':
                break
            elif line.startswith('"""', index):
                triple = True
                index += 3
            elif line[index] == '"':
                # Generalized/raw strings escape quotes by doubling; ordinary strings use backslashes.
                raw = index > 0 and (line[index - 1].isalnum() or line[index - 1] == '_')
                index += 1
                while index < len(line):
                    if raw and line.startswith('""', index):
                        index += 2
                    elif not raw and line[index] == '\\':
                        index += 2
                    elif line[index] == '"':
                        index += 1
                        break
                    else:
                        index += 1
            elif line[index] == "'" and (character := CHARACTER.match(line, index)):
                index = character.end()
            else:
                mask[index] = line[index]
                index += 1
        yield line, ''.join(mask), protected


def normalize_spacing(source):
    """Separate the license, module docs and top-level routines; allow one blank between sections.

    Preserve indented declaration groups and all multiline token contents. Attached line comments
    stay with their routine. This pass supplements nimpretty, which retains input blank-line runs.
    """
    rows = list(source_lines(source))
    boundaries = set()
    preamble = True
    # Determine section starts using lexical code, rather than text embedded in strings/comments.
    for index, (line, code, protected) in enumerate(rows):
        if not protected:
            if preamble and line.startswith('# SPDX-License-Identifier:'):
                boundaries.add(index + 1)
            if preamble and line.startswith('##') and not line.startswith('##['):
                # Only the end of a contiguous module documentation paragraph needs a separator.
                if index + 1 < len(rows) and not rows[index + 1][0].startswith('##'):
                    boundaries.add(index + 1)
            if code.strip():
                preamble = False
            if ROUTINE.match(code):
                start = index
                # Move the boundary before explanatory comments attached directly to the routine.
                while start and rows[start - 1][0].startswith('#') and not rows[start - 1][2]:
                    start -= 1
                boundaries.add(start)
    output = []
    # Collapse only source whitespace; never change blank lines inside multiline tokens.
    for index, (line, _, protected) in enumerate(rows):
        if index in boundaries and output and output[-1].strip():
            output.append('\n')
        if not protected and not line.strip():
            if output and output[-1].strip():
                output.append('\n')
        else:
            output.append(line)
    return ''.join(output)
