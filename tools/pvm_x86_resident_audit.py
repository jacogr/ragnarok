# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Fail closed on the linked two-borrow SysV sentinel path of the disposable proof."""
import re

SENTINELS = {
    'rbx': 0x0123456789abcdef, 'rbp': 0x123456789abcdef0, 'r12': 0x23456789abcdef01,
    'r13': 0x3456789abcdef012, 'r14': 0x456789abcdef0123, 'r15': 0x56789abcdef01234,
}
REGISTERS = re.compile(r'r(?:ax|bx|cx|dx|si|di|bp|sp|[89]|1[0-5])$')
NARROW = dict(eax='rax', ebx='rbx', ecx='rcx', edx='rdx', esi='rsi', edi='rdi',
              ebp='rbp', esp='rsp', **{f'r{i}{size}': f'r{i}'
                                     for i in range(8, 16) for size in 'dwb'})
NARROW.update({alias: 'r'+family for family, aliases in (
    ('ax', ('ax', 'al', 'ah')), ('bx', ('bx', 'bl', 'bh')), ('cx', ('cx', 'cl', 'ch')),
    ('dx', ('dx', 'dl', 'dh')), ('si', ('si', 'sil')), ('di', ('di', 'dil')),
    ('bp', ('bp', 'bpl')), ('sp', ('sp', 'spl'))) for alias in aliases})


def _instructions(output):
    rows = []
    for line in output.splitlines():
        columns = line.strip().split('\t', 2)
        if len(columns) != 3 or not re.fullmatch(r'[0-9a-f]+:', columns[0]):
            continue
        instruction = columns[2].split('#', 1)[0].strip().split(None, 1)
        if instruction:
            rows.append((int(columns[0][:-1], 16), instruction[0],
                         instruction[1].strip() if len(instruction) == 2 else ''))
    return rows


def _value(state, operand):
    if REGISTERS.fullmatch(operand):
        return state.get(operand)
    if re.fullmatch(r'0x[0-9a-f]+', operand):
        return int(operand, 16)
    return None


def _track(state, opcode, operand):
    """Track only unambiguous whole-register transfers and constant moves."""
    destination, _, source = operand.partition(',')
    destination, source = destination.strip(), source.strip()
    if opcode in ('mov', 'movabs') and REGISTERS.fullmatch(destination):
        state[destination] = _value(state, source)
    elif opcode == 'xchg':
        state.pop(NARROW.get(destination, destination), None)
        state.pop(NARROW.get(source, source), None)
    elif opcode not in ('cmp', 'test', 'push', 'nop') and not opcode.startswith('j'):
        destination = NARROW.get(destination, destination)
        state.pop(destination, None)


def _target(operand):
    match = re.match(r'([0-9a-f]+)(?:\s|$)', operand)
    if not match:
        raise ValueError('Missing linked x86 branch target')
    return int(match[1], 16)


def _aborts(rows, by_address, start):
    """Accept the diagnostic block's direct abort call, with optional outlining jump."""
    visited = set()
    diagnostic = False
    while 0 <= start < len(rows) and start not in visited:
        visited.add(start)
        _, opcode, operand = rows[start]
        if opcode == 'call':
            if operand.endswith(('<abort@plt>', '<abort>')):
                return diagnostic
            if not operand.endswith(('<fputs@plt>', '<fwrite@plt>')):
                return False
            diagnostic = True
        if opcode == 'jmp':
            start = by_address.get(_target(operand), -1)
            continue
        if opcode.startswith('j') or opcode in ('ret', 'ud2'):
            break
        start += 1
    return False


def audit_sentinels(output):
    """Require one actual two-borrow call and all six live comparisons on its return path."""
    rows = _instructions(output)
    transfers = [index for index, (_, opcode, operand) in enumerate(rows)
                 if opcode == 'call' and REGISTERS.fullmatch(operand)]
    if len(transfers) != 1:
        raise ValueError('Missing unique linked resident indirect call')
    call, = transfers
    state = dict(rdx='registers', rcx='context')
    initialized = {}
    for address, opcode, operand in rows[:call]:
        before = state.copy()
        _track(state, opcode, operand)
        for register, expected in SENTINELS.items():
            if state.get(register) == expected and before.get(register) != expected:
                initialized[register] = address
    if (state.get('rdi'), state.get('rsi')) != ('registers', 'context'):
        raise ValueError('Linked resident call does not borrow registers then context')
    if any(state.get(register) != expected for register, expected in SENTINELS.items()):
        raise ValueError('Missing linked sentinel initialization before resident call')

    first_init = min(initialized.values())
    call_address = rows[call][0]
    for _, opcode, operand in rows:
        if opcode.startswith('j') and first_init < _target(operand) <= call_address:
            raise ValueError('Linked resident call can bypass sentinel initialization')

    addresses = {address:index for index, (address, _, _) in enumerate(rows)}
    state = {register:register for register in SENTINELS}
    checks, visited = {}, set()
    index = call+1
    while 0 <= index < len(rows) and index not in visited and len(checks) < len(SENTINELS):
        visited.add(index)
        address, opcode, operand = rows[index]
        if opcode == 'cmp' and ',' in operand:
            left, right = (_value(state, item.strip()) for item in operand.split(',', 1))
            register, expected = (left, right) if left in SENTINELS else (right, left)
            if register in SENTINELS and expected == SENTINELS[register]:
                if index+1 >= len(rows):
                    raise ValueError('Missing linked sentinel mismatch branch')
                _, branch, edge = rows[index+1]
                if branch not in ('jne', 'jnz', 'je', 'jz'):
                    raise ValueError('Missing linked sentinel mismatch branch')
                target = addresses.get(_target(edge), -1)
                if branch in ('jne', 'jnz'):
                    next_index, mismatch = index+2, target
                else:
                    next_index, mismatch = target, index+2
                if not _aborts(rows, addresses, mismatch):
                    raise ValueError('Linked sentinel mismatch does not abort')
                checks[register] = address
                index = next_index
                continue
        if opcode == 'jmp':
            index = addresses.get(_target(operand), len(rows))
            continue
        if opcode.startswith('j') or opcode in ('call', 'ret', 'ud2'):
            break
        _track(state, opcode, operand)
        index += 1
    if checks.keys() != SENTINELS.keys():
        raise ValueError('Missing linked live sentinel comparisons')
    return dict(indirect_call=rows[call][0], checks=checks)


def audit_link(checks, binary, label):
    """Bind the actual linked Nim bridge and the C wrapper before entering any dumped leaf."""
    prefix = binary.read_bytes()[:20]
    if len(prefix) != 20 or prefix[:6] != b'\x7fELF\x02\x01' or prefix[18:20] != b'\x3e\x00':
        raise ValueError('Resident witness is not a little-endian amd64 ELF64')
    symbols = checks.command(['nm', '--defined-only', binary], label+'-linked-symbols')
    if symbols['exit_code']:
        raise RuntimeError('Resident witness symbol read failed')
    names = {}
    for key, pattern in (
            ('bridge', r'enterNativeReadBodyAbiProof_\w+(?:\.\w+)*'),
            ('wrapper', r'pvm_x86_checked_read_abi_proof(?:\.\w+)*')):
        matches = re.findall(r'(?m)^[0-9a-f]+\s+[tT]\s+('+pattern+r')$', symbols['output'])
        if len(matches) != 1:
            raise ValueError('Missing unique linked resident '+key)
        names[key] = matches[0]
    records = {}
    for key, symbol in names.items():
        row = checks.command(['objdump', '-dw', '-Mintel', '--disassemble='+symbol, binary],
                             label+'-linked-'+key)
        if row['exit_code']:
            raise RuntimeError('Resident witness disassembly failed')
        records[key] = row
    caller = _instructions(records['bridge']['output'])
    if not any(opcode == 'call' and operand.endswith('<'+names['wrapper']+'>')
               for _, opcode, operand in caller):
        raise ValueError('Linked checked-read ABI bridge does not call its audited wrapper')
    return dict(symbols=names, disassembly={key:row['log'] for key, row in records.items()},
                **audit_sentinels(records['wrapper']['output']))
