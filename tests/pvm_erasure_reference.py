# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent pinned-field Lagrange oracle; no production implementation or output is read."""

# Exponent lists transcribe the pinned Gray Paper table directly.
EXPONENTS = [
    [0], [15, 13, 11, 10, 7, 6, 3, 1], [13, 12, 11, 10, 3, 2, 1],
    [12, 10, 9, 5, 4, 3, 2, 1], [15, 14, 10, 8, 7, 1],
    [15, 14, 13, 11, 10, 8, 5, 3, 2, 1], [15, 12, 8, 6, 3, 2],
    [14, 4, 1], [14, 13, 11, 10, 7, 4, 3], [12, 7, 6, 4, 3],
    [14, 13, 11, 9, 6, 5, 4, 1], [15, 13, 12, 11, 8],
    [15, 14, 13, 12, 11, 10, 8, 7, 5, 4, 3],
    [15, 14, 13, 12, 11, 9, 8, 5, 4, 2],
    [15, 14, 13, 12, 11, 10, 9, 8, 5, 4, 3], [15, 12, 11, 8, 4, 3, 2, 1],
]
BASIS = [sum(1 << exponent for exponent in row) for row in EXPONENTS]


def polynomial(word):
    """Map Cantor coordinates to the explicit polynomial vector space."""
    value = 0
    for bit, column in enumerate(BASIS):
        # Only selected coordinates contribute in characteristic two.
        if word & (1 << bit):
            value ^= column
    return value


COORDINATES = {polynomial(word): word for word in range(65536)}


def multiply(left, right):
    """Carryless polynomial product followed by long division, unlike production shift/reduce."""
    product = 0
    for bit in range(16):
        if right & (1 << bit):
            product ^= left << bit
    for bit in range(30, 15, -1):
        if product & (1 << bit):
            product ^= 0x1002D << (bit - 16)
    return product


def inverse(value):
    """Extended polynomial Euclid, independent of production exponentiation."""
    assert value
    left, right, a, b = value, 0x1002D, 1, 0
    while left != 1:
        shift = left.bit_length() - right.bit_length()
        if shift < 0:
            left, right, a, b = right, left, b, a
            shift = -shift
        left ^= right << shift
        a ^= b << shift
    # Reduce the coefficient to its unique polynomial field representative.
    while a.bit_length() > 16:
        a ^= 0x1002D << (a.bit_length() - 17)
    return a


def interpolate(indices, words, targets):
    """Lagrange evaluation at arbitrary distinct coordinates, also used for erasure recovery."""
    assert len(indices) == len(set(indices)) == len(words)
    points = [polynomial(index) for index in indices]
    values = [polynomial(word) for word in words]
    weights = []
    for i, point in enumerate(points):
        denominator = 1
        for j, other in enumerate(points):
            if i != j:
                denominator = multiply(denominator, point ^ other)
        weights.append(multiply(values[i], inverse(denominator)))
    answer = []
    known = dict(zip(indices, words))
    for target in targets:
        if target in known:
            answer.append(known[target])
        else:
            point = polynomial(target)
            product = 1
            for other in points:
                product = multiply(product, point ^ other)
            total = 0
            for other, weight in zip(points, weights):
                total ^= multiply(weight, inverse(point ^ other))
            answer.append(COORDINATES[multiply(product, total)])
    return answer


def original_count(validators):
    """Find the maximum admissible divisor by enumeration, rather than descending search."""
    return max(d for d in range(1, validators // 3 + 2) if 2052 % d == 0)


def message(validators):
    """Exercise high bits and nonconstant independent coordinates with a fixed arithmetic pattern."""
    return [((i * 257 + 0x8123) ^ (i * i * 19)) & 65535 for i in range(original_count(validators))]


def witnesses():
    """Return complete expected words for every selected validator geometry."""
    return {v: interpolate(list(range(original_count(v))), message(v), range(v))
            for v in [6, 9, 51, 1023]}


if __name__ == '__main__':
    import json
    print(json.dumps(witnesses()))
