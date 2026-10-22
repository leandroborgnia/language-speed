// "Tuned C++" variants of the tests where idiomatic MSVC std:: code lost to Java.
#include <charconv>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
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

int main(int argc, char** argv) {
    string tmp = argc > 1 ? argv[1] : ".";

    const long long N_STR = 5000000;
    run("string_build_split_parse[to_chars/from_chars]", N_STR, [&] {
        string s; s.reserve(N_STR * 8); char b[24];
        for (long long i = 0; i < N_STR; i++) { auto r = to_chars(b, b + 24, i); s.append(b, r.ptr); s += ','; }
        long long sum = 0; const char* p = s.data(); const char* e = p + s.size();
        while (p < e) { long long v; auto r = from_chars(p, e, v); sum += v; p = r.ptr + 1; }
        return sum;
    });

    const long long N_MAP = 5000000;
    run("hashmap_insert_lookup[unordered_map+reserve]", N_MAP, [&] {
        unordered_map<long long, long long> m; m.reserve(N_MAP);
        for (long long i = 0; i < N_MAP; i++) m[(i * 2654435761LL) & 0xFFFFFFFF] = i;
        long long hit = 0;
        for (long long i = 0; i < N_MAP; i++) { auto it = m.find((i * 2654435761LL) & 0xFFFFFFFF); if (it != m.end()) hit += it->second & 1; }
        return hit;
    });
    run("hashmap_insert_lookup[open addressing]", N_MAP, [&] {
        size_t cap = 1 << 24, mask = cap - 1;               // 16M slots, load ~0.3
        vector<long long> keys(cap, -1), vals(cap);
        auto h = [&](long long k) { return (size_t)((uint64_t)k * 0x9E3779B97F4A7C15ULL >> 40) & mask; };
        for (long long i = 0; i < N_MAP; i++) { long long k = (i * 2654435761LL) & 0xFFFFFFFF; size_t s = h(k); while (keys[s] != -1 && keys[s] != k) s = (s + 1) & mask; keys[s] = k; vals[s] = i; }
        long long hit = 0;
        for (long long i = 0; i < N_MAP; i++) { long long k = (i * 2654435761LL) & 0xFFFFFFFF; size_t s = h(k); while (keys[s] != -1) { if (keys[s] == k) { hit += vals[s] & 1; break; } s = (s + 1) & mask; } }
        return hit;
    });

    struct Pt { double x, y; };
    const long long N_OBJ = 10000000;
    run("alloc_small_objects[by value, no heap/object]", N_OBJ, [&] {
        vector<Pt> v; v.reserve(N_OBJ);
        for (long long i = 0; i < N_OBJ; i++) v.push_back({ (double)i, (double)(i * 2) });
        double s = 0; for (auto& p : v) s += p.x + p.y;
        return (long long)s;
    });

    const long long N_LINES = 5000000;
    string lf = tmp + "/cppt_lines.txt";
    run("io_write_lines[to_chars + fwrite]", N_LINES, [&] {
        FILE* f = fopen(lf.c_str(), "wb"); vector<char> buf(1 << 20); size_t n = 0;
        for (long long i = 0; i < N_LINES; i++) {
            if (n > buf.size() - 64) { fwrite(buf.data(), 1, n, f); n = 0; }
            memcpy(&buf[n], "line ", 5); n += 5;
            n = to_chars(&buf[n], &buf[n] + 24, i).ptr - buf.data(); buf[n++] = ',';
            n = to_chars(&buf[n], &buf[n] + 24, i * 7).ptr - buf.data(); buf[n++] = '\n';
        }
        fwrite(buf.data(), 1, n, f); fclose(f); return N_LINES;
    });
    run("io_read_parse_lines[read whole file + from_chars]", N_LINES, [&] {
        FILE* f = fopen(lf.c_str(), "rb"); fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
        string d(sz, '\0'); fread(d.data(), 1, sz, f); fclose(f);
        long long sum = 0; const char* p = d.data(); const char* e = p + sz;
        while (p < e) { const char* c = (const char*)memchr(p, ',', e - p); long long v; auto r = from_chars(c + 1, e, v); sum += v; p = r.ptr + 1; }
        return sum;
    });
    remove(lf.c_str());
}
