"""Small CPU-only test to compare native Windows vs Linux container (WSL2 VM)."""
import platform, time

def xorshift(n):
    x, acc, M = 88172645463325252, 0, 0xFFFFFFFFFFFFFFFF
    for _ in range(n):
        x ^= (x << 13) & M; x ^= x >> 7; x ^= (x << 17) & M; acc += x & 0xFFFF
    return acc

def leibniz(n):
    s, sign = 0.0, 1.0
    for k in range(n):
        s += sign / (2.0 * k + 1.0); sign = -sign
    return s

def best(f, n):
    b = 1e9
    for _ in range(5):
        t = time.perf_counter(); f(n); b = min(b, time.perf_counter() - t)
    return b * 1e9 / n

print(f"{platform.system()} {platform.python_version()}: "
      f"xorshift {best(xorshift, 5_000_000):.1f} ns/op, leibniz {best(leibniz, 5_000_000):.1f} ns/op")
