# cython: language_level=3, boundscheck=False, wraparound=False, cdivision=True, initializedcheck=False
"""Benchmark suite v2 - Python compiled ahead-of-time with Cython (C typed loops; Python objects where the
test is about Python's own data structures: str, dict, list, file objects)."""
from libc.math cimport sin, sqrt


def int_lcg(long long n):
    cdef long long x = 88172645, acc = 0, i
    for i in range(n):
        x = (x * 1103515245LL + 12345) % 2147483648LL
        acc += x % 65536
    return acc

def int_collatz(long long n):
    cdef long long steps = 0, k, v
    for k in range(1, n + 1):
        v = k
        while v != 1:
            v = 3 * v + 1 if v % 2 == 1 else v // 2
            steps += 1
    return steps

def float_leibniz(long long n):
    cdef double s = 0.0, sign = 1.0
    cdef long long k
    for k in range(n):
        s += sign / (2.0 * k + 1.0); sign = -sign
    return <long long>(s * 4e9)

def mandel(int W, int H, int MAXI):
    cdef long long total = 0
    cdef int py, px, it
    cdef double ci, cr, zr, zi, t
    for py in range(H):
        ci = -1.25 + 2.5 * py / H
        for px in range(W):
            cr = -2.0 + 2.5 * px / W; zr = 0.0; zi = 0.0; it = 0
            while it < MAXI and zr * zr + zi * zi <= 4.0:
                t = zr * zr - zi * zi + cr; zi = 2.0 * zr * zi + ci; zr = t; it += 1
            total += it
    return total

def float_sin_sqrt(long long n):
    cdef double s = 0.0
    cdef long long i
    for i in range(n):
        s += sin(i * 0.001) * sqrt(<double>i)
    return <long long>s

def string_format_parse(long long n):
    cdef long long acc = 0, i
    cdef Py_ssize_t p
    cdef str s
    for i in range(n):
        s = "line " + str(i) + "," + str(i * 7)
        p = s.find(",")
        acc += int(s[p + 1:]) + len(s)
    return acc

def hashmap(long long n):
    cdef dict m = {}
    cdef long long i, hit = 0
    for i in range(n):
        m[(i * 2654435761LL) % 4294967296LL] = i
    for i in range(n):
        v = m.get((i * 2654435761LL) % 4294967296LL)
        if v is not None:
            hit += <long long>v % 2
    return hit

def sort_int64(long long n):
    cdef long long x = 88172645, i
    cdef list v = [0] * n
    for i in range(n):
        x = (x * 1103515245LL + 12345) % 2147483648LL
        v[i] = x
    v.sort()
    return v[0] + v[n // 2] + v[n - 1]

def io_write_lines(str path, long long n):
    cdef long long i
    with open(path, "w", buffering=1 << 16, newline="\n") as f:
        for i in range(n):
            f.write(f"line {i},{i * 7}\n")
    return n

def io_read_parse_lines(str path):
    cdef long long total = 0
    cdef str line
    with open(path, "r") as f:
        for line in f:
            total += int(line[line.index(",") + 1:])
    return total
