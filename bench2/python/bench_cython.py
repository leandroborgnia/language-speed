"""Driver for the Cython-compiled suite. Build first: python setup.py build_ext --inplace"""
import os, sys, time
import cy_bench as c

TMP = sys.argv[1] if len(sys.argv) > 1 else "."


def run(name, units, f, *args):
    best, chk = 1e99, 0
    for _ in range(3):
        t0 = time.perf_counter(); chk = f(*args); best = min(best, time.perf_counter() - t0)
    print(f"{name},{units},{best:.4f},{best * 1e9 / units:.3f},{chk}", flush=True)


run("int_lcg", 100_000_000, c.int_lcg, 100_000_000)
run("int_collatz", 131434424, c.int_collatz, 1_000_000)
run("float_leibniz", 100_000_000, c.float_leibniz, 100_000_000)
run("float_mandelbrot", c.mandel(1000, 1000, 200), c.mandel, 1000, 1000, 200)
run("float_sin_sqrt", 20_000_000, c.float_sin_sqrt, 20_000_000)
run("string_format_parse", 5_000_000, c.string_format_parse, 5_000_000)
run("hashmap_insert_lookup", 5_000_000, c.hashmap, 5_000_000)
run("sort_int64", 5_000_000, c.sort_int64, 5_000_000)
lf = os.path.join(TMP, "cy_lines.txt")
run("io_write_lines", 5_000_000, c.io_write_lines, lf, 5_000_000)
run("io_read_parse_lines", 5_000_000, c.io_read_parse_lines, lf)
os.remove(lf)
