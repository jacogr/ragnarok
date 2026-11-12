# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Normalize Nim section spacing without rewriting literal or block-comment contents."""
import re

ROUTINE = re.compile(r'^(?:proc|func|method|iterator|template|macro|converter)\s')
SECTION = re.compile(r'^(import|from|const|type)(?:\s|$)')
CHARACTER = re.compile(r"'(?:\\(?:[0-9]+|x[0-9a-fA-F]{2}|.)|[^'\\\n])'")


def source_lines(source):
    """Yield each line, its code mask, multiline protection and standalone comment status."""
    triple = False
    comments = 0
    comment_open = '#['
    comment_close = ']#'
    standalone_block = False
    # Keep state across lines so embedded snippets never become formatting instructions.
    # Nim recognizes CR/LF boundaries; Unicode separators remain literal UTF-8 contents.
    for line in re.findall(r'[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+$', source):
        protected = triple or comments > 0
        standalone_comment = standalone_block if comments else not triple and line.startswith('#')
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
                standalone_block = standalone_comment
                # Documentation comments treat plain ]# and #[ as text; ordinary comments do not.
                documentation = line.startswith('##[', index)
                comment_open = '##[' if documentation else '#['
                comment_close = ']##' if documentation else ']#'
                index += len(comment_open)
            elif line[index] == '#':
                break
            elif line.startswith('"""', index):
                standalone_comment = False
                triple = True
                index += 3
            elif line[index] == '"':
                standalone_comment = False
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
                standalone_comment = False
                index = character.end()
            else:
                if not line[index].isspace():
                    standalone_comment = False
                mask[index] = line[index]
                index += 1
        yield line, ''.join(mask), protected, standalone_comment


def normalize_spacing(source):
    """Separate the header, module docs, and top-level imports, consts, types and routines.

    Preserve indented declaration groups and all multiline token contents. Attached comments
    stay with the section they introduce. Nimpretty retains input blank-line runs.
    """
    rows = list(source_lines(source))
    boundaries = set()
    preamble = True
    previous_section = None
    # Determine section starts using lexical code, rather than text embedded in strings/comments.
    for index, (line, code, protected, _) in enumerate(rows):
        if not protected:
            if preamble and line.startswith('# SPDX-License-Identifier:'):
                boundaries.add(index + 1)
            if preamble and line.startswith('##') and not line.startswith('##['):
                # Only the end of a contiguous module documentation paragraph needs a separator.
                if index + 1 < len(rows) and not rows[index + 1][0].startswith('##'):
                    boundaries.add(index + 1)
            if code.strip():
                preamble = False
            new_section = False
            # Indented bodies and unindented closing delimiters belong to the preceding statement.
            if code.strip() and not code[0].isspace() and code[0] not in ')]},':
                match = SECTION.match(code)
                section = match[1] if match else None
                if section == 'from':
                    section = 'import'
                new_section = (section is not None and previous_section is not None
                               and section != previous_section)
                previous_section = section
            if new_section or ROUTINE.match(code):
                start = index
                # Move the boundary before explanatory comments attached directly to the declaration.
                while start and rows[start - 1][3]:
                    start -= 1
                boundaries.add(start)
    output = []
    # Collapse only source whitespace; never change blank lines inside multiline tokens.
    for index, (line, _, protected, _) in enumerate(rows):
        if index in boundaries and output and output[-1].strip():
            output.append('\n')
        if not protected and not line.strip():
            if output and output[-1].strip():
                output.append('\n')
        else:
            output.append(line)
    return ''.join(output)
