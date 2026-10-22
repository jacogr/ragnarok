# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Read PSI memory snapshots as contextual stall observations, without attributing them to a child."""
import re
from storage_limit_budget import natural


def parse_psi(raw):
    """Require both memory stall classes and their exact finite percentage/time fields."""
    if type(raw) is not str or len(raw)>4096:
        raise ValueError('Invalid memory PSI extent')
    result={}
    for line in raw.splitlines():
        fields=line.split()
        if len(fields)!=5 or fields[0] not in ('some','full') or fields[0] in result:
            raise ValueError('Invalid memory PSI class')
        row={}
        for key,field in zip(('avg10','avg60','avg300','total'),fields[1:]):
            name,sep,value=field.partition('=')
            if not sep or name!=key:
                raise ValueError('Invalid memory PSI field order')
            if key=='total':
                row[key]=natural(value)
            else:
                # Kernel percentages retain their two-decimal canonical representation.
                if re.fullmatch(r'(0|[1-9][0-9]{0,2})\.[0-9]{2}',value) is None or float(value)>100:
                    raise ValueError('Invalid memory PSI percentage')
                row[key]=float(value)
        result[fields[0]]=row
    if set(result)!= {'some','full'}:
        raise ValueError('Incomplete memory PSI classes')
    return result
