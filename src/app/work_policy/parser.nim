# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private shared strict policy lexing and reviewed nominal scalar conversion; the common error and backend domains remain independently importable.

import ./types
import ../../pvm/backend

type
  PolicyValue = object ## Extents and fixed key count are proved before appending bounded owned strings.
    name, text: string
    used: bool
  PolicyInput = object ## First selected conversion/missing error remains private through complete schema visitation.
    values: seq[PolicyValue]
    error: WorkPolicyError
    field: string

proc decimal(text: string, number: var uint64): bool =
  ## Canonical unsigned decimal accepts no signs, padding, spaces or wrapping multiplication.
  number = 0
  if text.len == 0 or text.len > 20: return false
  if text.len > 1 and text[0] == '0': return false
  for character in text:
    if character notin {'0'..'9'}: return false
    let digit = uint64(ord(character)-ord('0'))
    if number > (high(uint64)-digit) div 10: return false
    number = number*10+digit
  true

proc readField[T](input: var PolicyInput, name: string, field: var T) {.untyped.} =
  ## Only reviewed nominal unsigned widths and the closed backend enum can instantiate this schema.
  if input.error notin [WorkPolicyError.None, WorkPolicyError.MissingField]: return
  for index in 0..<input.values.len:
    if input.values[index].name == name:
      let text = input.values[index].text
      when T is PvmBackend:
        # A named engine is required; enum ordinals cannot silently change meaning after an engine is removed.
        if not parsePvmBackend(text, field):
          input.error = WorkPolicyError.InvalidBackend
          input.field = name
          return
      else:
        # Prove full uint64 parsing and any narrower nominal extent before assigning.
        var number = 0'u64
        if not decimal(text, number):
          input.error = WorkPolicyError.InvalidNumber
          input.field = name
          return
        when sizeof(T) == 4:
          if number > uint64(high(uint32)):
            input.error = WorkPolicyError.InvalidNumber
            input.field = name
            return
        elif sizeof(T) != 8:
          {.error: "work policy leaves require reviewed unsigned 32/64-bit domains".}
        field = T(number)
      input.values[index].used = true
      return
  if input.error == WorkPolicyError.None:
    input.error = WorkPolicyError.MissingField
    input.field = name

proc writeField[T](text: var string, name: string, field: T) {.untyped.} =
  ## Emit every declared value without synthesizing execution budgets or serializing logging pointers.
  when T is PvmBackend: text.add(name & "=" & $field & "\n")
  else: text.add(name & "=" & $uint64(field) & "\n")

func inputFailure(reason: WorkPolicyError, field = ""): PolicyInput =
  ## Lexical refusal contains no parsed field prefix or activation object.
  PolicyInput(values: @[], error: reason, field: field)

proc parsePolicyInput(text, header: string, maximumBytes, maximumFields: int): PolicyInput =
  ## Both explicit policy versions share the same bounded lexical grammar without guessing headers, numbers or duplicate precedence.
  if text.len > maximumBytes: return inputFailure(WorkPolicyError.LimitExceeded)
  var input = PolicyInput(values: @[], error: WorkPolicyError.None)
  var position, line = 0
  while position < text.len:
    let first = position
    while position < text.len and text[position] != '\n': inc position
    let extent = position-first
    if line == 0:
      if extent != header.len: return inputFailure(WorkPolicyError.WrongVersion)
      if text.substr(first, position-1) != header: return inputFailure(
          WorkPolicyError.WrongVersion)
    elif extent > 0 and text[first] != '#':
      # A complete line is bounded before copying either key or named/numeric value.
      if extent > 257: return inputFailure(WorkPolicyError.LimitExceeded)
      var separator = -1
      for index in first..<position:
        let character = text[index]
        if character == '=':
          if separator >= 0: return inputFailure(WorkPolicyError.InvalidLine)
          separator = index
        elif separator < 0 and character notin {'a'..'z', 'A'..'Z', '0'..'9', '.'}:
          return inputFailure(WorkPolicyError.InvalidLine)
      if separator <= first or separator-first > 192 or separator+1 == position:
        return inputFailure(WorkPolicyError.InvalidLine)
      if position-separator-1 > 64: return inputFailure(WorkPolicyError.LimitExceeded)
      let name = text.substr(first, separator-1)
      for previous in input.values:
        if previous.name == name: return inputFailure(WorkPolicyError.DuplicateField, name)
      if input.values.len == maximumFields: return inputFailure(WorkPolicyError.LimitExceeded)
      input.values.add(PolicyValue(name: name, text: text.substr(separator+1, position-1)))
    inc line
    if position < text.len: inc position
  if line == 0: return inputFailure(WorkPolicyError.WrongVersion)
  input
