// Single-threaded micro benchmarks. Build: cl /O2 /EHsc /std:c++17 bench.cpp
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <fstream>
#include <functional>
#include <memory>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std;
using clk = chrono::steady_clock;
static string TMP;

static void run(const char* name, long long units, const function<long long()>& f) {
    double best = 1e99; long long chk = 0;
    for (int r = 0; r < 3; r++) {
        auto t0 = clk::now();
        chk = f();
        double s = chrono::duration<double>(clk::now() - t0).count();
        best = min(best, s);
    }
    printf("%s,%lld,%.4f,%.3f,%lld\n", name, units, best, best * 1e9 / units, chk);
    fflush(stdout);
}

int main(int argc, char** argv) {
    TMP = argc > 1 ? argv[1] : ".";

    const long long N_MIX = 100000000;
    run("int_xorshift", N_MIX, [&] {
        uint64_t x = 88172645463325252ULL, acc = 0;
        for (long long i = 0; i < N_MIX; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; acc += x & 0xFFFF; }
        return (long long)acc;
    });

    const long long N_COL = 1000000;
    run("int_collatz(per number)", N_COL, [&] {
        long long steps = 0;
        for (long long n = 1; n <= N_COL; n++) { long long v = n; while (v != 1) { v = (v & 1) ? 3 * v + 1 : v / 2; steps++; } }
        return steps;
    });

    const long long N_LEIB = 100000000;
    run("float_leibniz", N_LEIB, [&] {
        double s = 0, sign = 1;
        for (long long k = 0; k < N_LEIB; k++) { s += sign / (2.0 * k + 1.0); sign = -sign; }
        return (long long)(s * 4e9);
    });

    const long long N_MATH = 20000000;
    run("float_sin_sqrt", N_MATH, [&] {
        double s = 0;
        for (long long i = 0; i < N_MATH; i++) s += sin(i * 0.001) * sqrt((double)i);
        return (long long)s;
    });

    // DECIMAL(18,4)-style fixed point on int64 (C++ has no decimal type)
    const long long N_DEC = 5000000;
    run("decimal_fixed(int64 scaled)", N_DEC, [&] {
        long long acc = 0;                       // scale 4
        for (long long i = 0; i < N_DEC; i++) {
            long long price = i % 10000;         // scale 2
            long long p = price * 10375;         // scale 6  (rate 1.0375)
            acc += (p + 50) / 100;               // round half up to scale 4
        }
        return acc;
    });

    const long long N_STR = 5000000;
    run("string_build_split_parse", N_STR, [&] {
        string s; s.reserve(0);
        for (long long i = 0; i < N_STR; i++) { s += to_string(i); s += ','; }
        long long sum = 0; size_t start = 0;
        while (true) {
            size_t p = s.find(',', start);
            if (p == string::npos) break;
            sum += stoll(s.substr(start, p - start));
            start = p + 1;
        }
        return sum;
    });

    const long long N_MAP = 5000000;
    run("hashmap_insert_lookup", N_MAP, [&] {
        unordered_map<long long, long long> m;
        for (long long i = 0; i < N_MAP; i++) m[(i * 2654435761LL) & 0xFFFFFFFF] = i;
        long long hit = 0;
        for (long long i = 0; i < N_MAP; i++) { auto it = m.find((i * 2654435761LL) & 0xFFFFFFFF); if (it != m.end()) hit += it->second & 1; }
        return hit;
    });

    const long long N_SORT = 5000000;
    run("sort_int64", N_SORT, [&] {
        mt19937_64 rng(42); vector<long long> v(N_SORT);
        for (auto& e : v) e = (long long)(rng() >> 1);
        sort(v.begin(), v.end());
        return v[N_SORT / 2] % 1000000;
    });

    struct Pt { double x, y; };
    const long long N_OBJ = 10000000;
    run("alloc_small_objects", N_OBJ, [&] {
        vector<unique_ptr<Pt>> v; v.reserve(N_OBJ);
        for (long long i = 0; i < N_OBJ; i++) v.push_back(make_unique<Pt>(Pt{ (double)i, (double)(i * 2) }));
        double s = 0; for (auto& p : v) s += p->x + p->y;
        return (long long)s;
    });

    const long long N_LINES = 5000000;
    string lf = TMP + "/cpp_lines.txt";
    run("io_write_lines", N_LINES, [&] {
        FILE* f = fopen(lf.c_str(), "wb"); setvbuf(f, nullptr, _IOFBF, 1 << 16);
        for (long long i = 0; i < N_LINES; i++) fprintf(f, "line %lld,%lld\n", i, i * 7);
        fclose(f); return N_LINES;
    });
    run("io_read_parse_lines", N_LINES, [&] {
        ifstream in(lf, ios::binary); string line; long long sum = 0;
        while (getline(in, line)) { size_t c = line.find(','); sum += stoll(line.substr(c + 1)); }
        return sum;
    });

    const long long MB = 512;
    string bf = TMP + "/cpp_bulk.bin";
    run("io_bulk_write(per MB)", MB, [&] {
        vector<char> buf(1 << 20, 'x'); FILE* f = fopen(bf.c_str(), "wb");
        for (long long i = 0; i < MB; i++) fwrite(buf.data(), 1, buf.size(), f);
        fclose(f); return MB;
    });
    run("io_bulk_read(per MB)", MB, [&] {
        vector<char> buf(1 << 20); FILE* f = fopen(bf.c_str(), "rb"); long long n = 0, x = 0;
        size_t r; while ((r = fread(buf.data(), 1, buf.size(), f)) > 0) { n += r; x += buf[0]; }
        fclose(f); return n >> 20;
    });
    remove(lf.c_str()); remove(bf.c_str());
}
