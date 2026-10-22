"""Single-threaded micro benchmarks. Run: python bench.py <tmpdir> [scale_divisor]
Pure-Python loops are slow, so loop-heavy tests use smaller N (results are per-op, so still comparable).
"""
import math, os, random, sys, time
from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP, getcontext

TMP = sys.argv[1] if len(sys.argv) > 1 else "."
D = int(sys.argv[2]) if len(sys.argv) > 2 else 20  # shrink loop-heavy tests by this factor


def run(name, units, f):
    best, chk = 1e99, 0
    for _ in range(3):
        t0 = time.perf_counter()
        chk = f()
        best = min(best, time.perf_counter() - t0)
    print(f"{name},{units},{best:.4f},{best * 1e9 / units:.3f},{chk}", flush=True)


N_MIX = 100_000_000 // D
def int_xorshift():
    x, acc, M = 88172645463325252, 0, 0xFFFFFFFFFFFFFFFF
    for _ in range(N_MIX):
        x ^= (x << 13) & M; x ^= x >> 7; x ^= (x << 17) & M; acc += x & 0xFFFF
    return acc
run("int_xorshift", N_MIX, int_xorshift)

N_COL = 1_000_000 // D
def int_collatz():
    steps = 0
    for n in range(1, N_COL + 1):
        v = n
        while v != 1:
            v = 3 * v + 1 if v & 1 else v // 2
            steps += 1
    return steps
run("int_collatz(per number)", N_COL, int_collatz)

N_LEIB = 100_000_000 // D
def float_leibniz():
    s, sign = 0.0, 1.0
    for k in range(N_LEIB):
        s += sign / (2.0 * k + 1.0); sign = -sign
    return int(s * 4e9)
run("float_leibniz", N_LEIB, float_leibniz)

N_MATH = 20_000_000 // D
def float_sin_sqrt():
    s, sin, sqrt = 0.0, math.sin, math.sqrt
    for i in range(N_MATH):
        s += sin(i * 0.001) * sqrt(i)
    return int(s)
run("float_sin_sqrt", N_MATH, float_sin_sqrt)

N_DEC = 5_000_000 // D
def decimal_fixed():
    acc = 0
    for i in range(N_DEC):
        acc += ((i % 10000) * 10375 + 50) // 100
    return acc
run("decimal_fixed(int64 scaled)", N_DEC, decimal_fixed)

def decimal_module():
    getcontext().prec = 38
    rate, acc, q = Decimal("1.0375"), Decimal(0), Decimal("0.0001")
    for i in range(N_DEC):
        price = Decimal(i % 10000).scaleb(-2)
        acc += (price * rate).quantize(q, rounding=ROUND_HALF_UP)
    return int(acc * 10000)
run("decimal_module(Decimal)", N_DEC, decimal_module)

N_STR = 5_000_000  # mostly C-implemented builtins, so full size
def string_build_split_parse():
    s = ",".join(str(i) for i in range(N_STR)) + ","
    return sum(int(p) for p in s.split(",") if p)
run("string_build_split_parse", N_STR, string_build_split_parse)

N_MAP = 5_000_000
def hashmap():
    m = {}
    for i in range(N_MAP):
        m[(i * 2654435761) & 0xFFFFFFFF] = i
    hit = 0
    for i in range(N_MAP):
        v = m.get((i * 2654435761) & 0xFFFFFFFF)
        if v is not None:
            hit += v & 1
    return hit
run("hashmap_insert_lookup", N_MAP, hashmap)

N_SORT = 5_000_000
def sort_int64():
    rng = random.Random(42)
    v = [rng.getrandbits(63) for _ in range(N_SORT)]
    v.sort()
    return v[N_SORT // 2] % 1000000
run("sort_int64", N_SORT, sort_int64)

@dataclass(slots=True)
class Pt:
    x: float
    y: float

N_OBJ = 10_000_000 // 5
def alloc():
    v = [Pt(float(i), float(i * 2)) for i in range(N_OBJ)]
    return int(sum(p.x + p.y for p in v))
run("alloc_small_objects", N_OBJ, alloc)

N_LINES = 5_000_000
lf = os.path.join(TMP, "py_lines.txt")
def io_write():
    with open(lf, "w", buffering=1 << 16, newline="\n") as f:
        for i in range(N_LINES):
            f.write(f"line {i},{i * 7}\n")
    return N_LINES
run("io_write_lines", N_LINES, io_write)

def io_read():
    total = 0
    with open(lf, "r") as f:
        for line in f:
            total += int(line[line.index(",") + 1:])
    return total
run("io_read_parse_lines", N_LINES, io_read)

MB = 512
bf = os.path.join(TMP, "py_bulk.bin")
def bulk_write():
    buf = b"x" * (1 << 20)
    with open(bf, "wb") as f:
        for _ in range(MB):
            f.write(buf)
    return MB
run("io_bulk_write(per MB)", MB, bulk_write)

def bulk_read():
    n = 0
    with open(bf, "rb", buffering=0) as f:
        buf = bytearray(1 << 20); mv = memoryview(buf)
        while (r := f.readinto(mv)):
            n += r
    return n >> 20
run("io_bulk_read(per MB)", MB, bulk_read)

# Bonus: the "idiomatic escape hatch" -- the same Leibniz sum vectorised with numpy
try:
    import numpy as np
    NL = 100_000_000
    def leib_np():
        s = 0.0
        for start in range(0, NL, 10_000_000):
            k = np.arange(start, start + 10_000_000, dtype=np.float64)
            s += float(np.sum(np.where(k % 2 == 0, 1.0, -1.0) / (2.0 * k + 1.0)))
        return int(s * 4e9)
    run("float_leibniz_numpy", NL, leib_np)
except ImportError:
    pass

os.remove(lf); os.remove(bf)
