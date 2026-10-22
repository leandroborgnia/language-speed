// Benchmark suite v2 - C++ (MSVC /O2). Same algorithms as Java / Python(Numba, Cython) / T-SQL native procs.
// Build: cl /O2 /GL /EHsc /std:c++17 /fp:precise bench.cpp
#include <algorithm>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>
using namespace std;
using clk = chrono::steady_clock;

static void run(const char* name, long long units, const function<long long()>& f) {
    double best = 1e99; long long chk = 0;
    for (int r = 0; r < 3; r++) { auto t0 = clk::now(); chk = f(); best = min(best, chrono::duration<double>(clk::now() - t0).count()); }
    printf("%s,%lld,%.4f,%.3f,%lld\n", name, units, best, best * 1e9 / units, chk); fflush(stdout);
}

static const long long M31 = 2147483648LL;

int main(int argc, char** argv) {
    string tmp = argc > 1 ? argv[1] : ".";

    const long long N_LCG = 100000000;
    run("int_lcg", N_LCG, [&] {
        long long x = 88172645, acc = 0;
        for (long long i = 0; i < N_LCG; i++) { x = (x * 1103515245LL + 12345) % M31; acc += x % 65536; }
        return acc;
    });

    const long long N_COL = 1000000, COL_STEPS = 131434424;   // units = total steps
    run("int_collatz", COL_STEPS, [&] {
        long long steps = 0;
        for (long long n = 1; n <= N_COL; n++) { long long v = n; while (v != 1) { v = (v % 2 == 1) ? 3 * v + 1 : v / 2; steps++; } }
        return steps;
    });

    const long long N_LEIB = 100000000;
    run("float_leibniz", N_LEIB, [&] {
        double s = 0, sign = 1;
        for (long long k = 0; k < N_LEIB; k++) { s += sign / (2.0 * k + 1.0); sign = -sign; }
        return (long long)(s * 4e9);
    });

    const int W = 1000, H = 1000, MAXI = 200;
    long long mandelIters = 0;
    auto mandel = [&] {
        long long total = 0;
        for (int py = 0; py < H; py++) {
            double ci = -1.25 + 2.5 * py / H;
            for (int px = 0; px < W; px++) {
                double cr = -2.0 + 2.5 * px / W, zr = 0, zi = 0; int it = 0;
                while (it < MAXI && zr * zr + zi * zi <= 4.0) { double t = zr * zr - zi * zi + cr; zi = 2.0 * zr * zi + ci; zr = t; it++; }
                total += it;
            }
        }
        return total;
    };
    mandelIters = mandel();
    run("float_mandelbrot", mandelIters, mandel);

    const long long N_MATH = 20000000;
    run("float_sin_sqrt", N_MATH, [&] {
        double s = 0;
        for (long long i = 0; i < N_MATH; i++) s += sin(i * 0.001) * sqrt((double)i);
        return (long long)s;
    });

    const long long N_STR = 5000000;
    run("string_format_parse", N_STR, [&] {
        long long acc = 0;
        for (long long i = 0; i < N_STR; i++) {
            string s = "line " + to_string(i) + "," + to_string(i * 7);
            size_t p = s.find(',');
            acc += stoll(s.substr(p + 1)) + (long long)s.size();
        }
        return acc;
    });
    run("string_format_parse[tuned]", N_STR, [&] {
        long long acc = 0; char b[48];
        for (long long i = 0; i < N_STR; i++) {
            memcpy(b, "line ", 5); char* e = to_chars(b + 5, b + 48, i).ptr; *e++ = ','; e = to_chars(e, b + 48, i * 7).ptr;
            const char* c = (const char*)memchr(b, ',', e - b); long long v; from_chars(c + 1, e, v);
            acc += v + (e - b);
        }
        return acc;
    });

    const long long N_MAP = 5000000;
    run("hashmap_insert_lookup", N_MAP, [&] {
        unordered_map<long long, long long> m; m.reserve(N_MAP);
        for (long long i = 0; i < N_MAP; i++) m[(i * 2654435761LL) % 4294967296LL] = i;
        long long hit = 0;
        for (long long i = 0; i < N_MAP; i++) { auto it = m.find((i * 2654435761LL) % 4294967296LL); if (it != m.end()) hit += it->second % 2; }
        return hit;
    });
    run("hashmap_insert_lookup[tuned]", N_MAP, [&] {
        size_t cap = 1 << 24, mask = cap - 1; vector<long long> keys(cap, -1), vals(cap);
        auto h = [&](long long k) { return (size_t)((uint64_t)k * 0x9E3779B97F4A7C15ULL >> 40) & mask; };
        for (long long i = 0; i < N_MAP; i++) { long long k = (i * 2654435761LL) % 4294967296LL; size_t s = h(k); while (keys[s] != -1 && keys[s] != k) s = (s + 1) & mask; keys[s] = k; vals[s] = i; }
        long long hit = 0;
        for (long long i = 0; i < N_MAP; i++) { long long k = (i * 2654435761LL) % 4294967296LL; size_t s = h(k); while (keys[s] != -1) { if (keys[s] == k) { hit += vals[s] % 2; break; } s = (s + 1) & mask; } }
        return hit;
    });

    const long long N_SORT = 5000000;
    run("sort_int64", N_SORT, [&] {
        vector<long long> v(N_SORT); long long x = 88172645;
        for (auto& e : v) { x = (x * 1103515245LL + 12345) % M31; e = x; }
        sort(v.begin(), v.end());
        return v[0] + v[N_SORT / 2] + v[N_SORT - 1];
    });

    const long long N_LINES = 5000000;
    string lf = tmp + "/cpp2_lines.txt";
    run("io_write_lines", N_LINES, [&] {
        ofstream o(lf, ios::binary);
        for (long long i = 0; i < N_LINES; i++) o << "line " << i << ',' << i * 7 << '\n';
        return N_LINES;
    });
    run("io_read_parse_lines", N_LINES, [&] {
        ifstream in(lf, ios::binary); string line; long long sum = 0;
        while (getline(in, line)) { size_t c = line.find(','); sum += stoll(line.substr(c + 1)); }
        return sum;
    });
    run("io_write_lines[tuned]", N_LINES, [&] {
        FILE* f = fopen(lf.c_str(), "wb"); vector<char> buf(1 << 20); size_t n = 0;
        for (long long i = 0; i < N_LINES; i++) {
            if (n > buf.size() - 64) { fwrite(buf.data(), 1, n, f); n = 0; }
            memcpy(&buf[n], "line ", 5); n += 5;
            n = to_chars(&buf[n], &buf[n] + 24, i).ptr - buf.data(); buf[n++] = ',';
            n = to_chars(&buf[n], &buf[n] + 24, i * 7).ptr - buf.data(); buf[n++] = '\n';
        }
        fwrite(buf.data(), 1, n, f); fclose(f); return N_LINES;
    });
    run("io_read_parse_lines[tuned]", N_LINES, [&] {
        FILE* f = fopen(lf.c_str(), "rb"); fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
        string d(sz, '\0'); fread(d.data(), 1, sz, f); fclose(f);
        long long sum = 0; const char* p = d.data(); const char* e = p + sz;
        while (p < e) { const char* c = (const char*)memchr(p, ',', e - p); long long v; auto r = from_chars(c + 1, e, v); sum += v; p = r.ptr + 1; }
        return sum;
    });
    remove(lf.c_str());
}
