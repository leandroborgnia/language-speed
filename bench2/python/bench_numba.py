"""Benchmark suite v2 - Python compiled with Numba (LLVM JIT, nopython mode). Run with the D: venv.
First call of each function compiles it; best of 3 excludes that (like Java's JIT warm-up)."""
import math, sys, time
import numpy as np
from numba import njit, types
from numba.typed import Dict

M31 = 2147483648


def run(name, units, f, *args):
    best, chk = 1e99, 0
    for _ in range(3):
        t0 = time.perf_counter(); chk = f(*args); best = min(best, time.perf_counter() - t0)
    print(f"{name},{units},{best:.4f},{best * 1e9 / units:.3f},{chk}", flush=True)


@njit
def int_lcg(n):
    x = 88172645; acc = 0
    for i in range(n):
        x = (x * 1103515245 + 12345) % M31
        acc += x % 65536
    return acc

@njit
def int_collatz(n):
    steps = 0
    for k in range(1, n + 1):
        v = k
        while v != 1:
            v = 3 * v + 1 if v % 2 == 1 else v // 2
            steps += 1
    return steps

@njit
def float_leibniz(n):
    s = 0.0; sign = 1.0
    for k in range(n):
        s += sign / (2.0 * k + 1.0); sign = -sign
    return int(s * 4e9)

@njit
def mandel(W, H, MAXI):
    total = 0
    for py in range(H):
        ci = -1.25 + 2.5 * py / H
        for px in range(W):
            cr = -2.0 + 2.5 * px / W; zr = 0.0; zi = 0.0; it = 0
            while it < MAXI and zr * zr + zi * zi <= 4.0:
                t = zr * zr - zi * zi + cr; zi = 2.0 * zr * zi + ci; zr = t; it += 1
            total += it
    return total

@njit
def float_sin_sqrt(n):
    s = 0.0
    for i in range(n):
        s += math.sin(i * 0.001) * math.sqrt(i)
    return int(s)

@njit
def parse_int(s):  # numba has no int(str); manual digit loop instead
    v = 0
    for ch in s:
        v = v * 10 + (ord(ch) - 48)
    return v

@njit
def string_format_parse(n):
    acc = 0
    for i in range(n):
        s = "line " + str(i) + "," + str(i * 7)
        p = s.find(",")
        acc += parse_int(s[p + 1:]) + len(s)
    return acc

@njit
def hashmap(n):
    m = Dict.empty(key_type=types.int64, value_type=types.int64)
    for i in range(n):
        m[(i * 2654435761) % 4294967296] = i
    hit = 0
    for i in range(n):
        k = (i * 2654435761) % 4294967296
        if k in m:
            hit += m[k] % 2
    return hit

@njit
def sort_int64(n):
    v = np.empty(n, dtype=np.int64); x = 88172645
    for i in range(n):
        x = (x * 1103515245 + 12345) % M31; v[i] = x
    v.sort()
    return v[0] + v[n // 2] + v[n - 1]


run("int_lcg", 100_000_000, int_lcg, 100_000_000)
run("int_collatz", 131434424, int_collatz, 1_000_000)
run("float_leibniz", 100_000_000, float_leibniz, 100_000_000)
run("float_mandelbrot", mandel(1000, 1000, 200), mandel, 1000, 1000, 200)
run("float_sin_sqrt", 20_000_000, float_sin_sqrt, 20_000_000)
try:
    run("string_format_parse", 5_000_000, string_format_parse, 5_000_000)
except Exception as e:  # Numba's string support is partial
    print(f"string_format_parse,n/a,,,unsupported in numba: {type(e).__name__}: {str(e).splitlines()[0][:120]}")
run("hashmap_insert_lookup", 5_000_000, hashmap, 5_000_000)
run("sort_int64", 5_000_000, sort_int64, 5_000_000)
print("io_write_lines,n/a,,,numba cannot do file IO in compiled code")
