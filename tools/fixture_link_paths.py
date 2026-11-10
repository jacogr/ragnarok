# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Locate a declared digest field in frozen fixture evidence."""


def locate(record, field):
    """Return the parent and leaf key of a link, or None if the field is absent."""
    while True:
        if isinstance(record, dict) and field in record:
            # Reporting maps use full filenames as keys, including their dots.
            return record, field
        component, dot, field = field.partition('.')
        if not dot:
            return None
        if isinstance(record, dict):
            record = record.get(component)
        elif isinstance(record, list) and component.isdecimal() and int(component) < len(record):
            record = record[int(component)]
        else:
            return None
