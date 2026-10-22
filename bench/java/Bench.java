// Single-threaded micro benchmarks. Run: java Bench.java <tmpdir>   (or javac + java)
import java.io.*;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.file.*;
import java.util.*;
import java.util.function.LongSupplier;

public class Bench {
    static void run(String name, long units, LongSupplier f) {
        double best = 1e99; long chk = 0;
        for (int r = 0; r < 3; r++) {   // runs 1-2 also serve as JIT warm-up
            long t0 = System.nanoTime();
            chk = f.getAsLong();
            best = Math.min(best, (System.nanoTime() - t0) / 1e9);
        }
        System.out.printf(Locale.ROOT, "%s,%d,%.4f,%.3f,%d%n", name, units, best, best * 1e9 / units, chk);
    }

    record Pt(double x, double y) {}

    public static void main(String[] a) throws Exception {
        String tmp = a.length > 0 ? a[0] : ".";

        final long N_MIX = 100_000_000L;
        run("int_xorshift", N_MIX, () -> {
            long x = 88172645463325252L, acc = 0;
            for (long i = 0; i < N_MIX; i++) { x ^= x << 13; x ^= x >>> 7; x ^= x << 17; acc += x & 0xFFFF; }
            return acc;
        });

        final long N_COL = 1_000_000L;
        run("int_collatz(per number)", N_COL, () -> {
            long steps = 0;
            for (long n = 1; n <= N_COL; n++) { long v = n; while (v != 1) { v = (v & 1) != 0 ? 3 * v + 1 : v / 2; steps++; } }
            return steps;
        });

        final long N_LEIB = 100_000_000L;
        run("float_leibniz", N_LEIB, () -> {
            double s = 0, sign = 1;
            for (long k = 0; k < N_LEIB; k++) { s += sign / (2.0 * k + 1.0); sign = -sign; }
            return (long) (s * 4e9);
        });

        final long N_MATH = 20_000_000L;
        run("float_sin_sqrt", N_MATH, () -> {
            double s = 0;
            for (long i = 0; i < N_MATH; i++) s += Math.sin(i * 0.001) * Math.sqrt((double) i);
            return (long) s;
        });

        final long N_DEC = 5_000_000L;
        run("decimal_fixed(int64 scaled)", N_DEC, () -> {
            long acc = 0;
            for (long i = 0; i < N_DEC; i++) { long p = (i % 10000) * 10375; acc += (p + 50) / 100; }
            return acc;
        });
        run("decimal_BigDecimal", N_DEC, () -> {
            BigDecimal rate = new BigDecimal("1.0375"), acc = BigDecimal.ZERO;
            for (long i = 0; i < N_DEC; i++) {
                BigDecimal price = BigDecimal.valueOf(i % 10000, 2);
                acc = acc.add(price.multiply(rate).setScale(4, RoundingMode.HALF_UP));
            }
            return acc.unscaledValue().longValue();
        });

        final long N_STR = 5_000_000L;
        run("string_build_split_parse", N_STR, () -> {
            StringBuilder sb = new StringBuilder();
            for (long i = 0; i < N_STR; i++) sb.append(i).append(',');
            String s = sb.toString(); long sum = 0; int start = 0, p;
            while ((p = s.indexOf(',', start)) >= 0) { sum += Long.parseLong(s, start, p, 10); start = p + 1; }
            return sum;
        });

        final int N_MAP = 5_000_000;
        run("hashmap_insert_lookup", N_MAP, () -> {
            HashMap<Long, Long> m = new HashMap<>();
            for (long i = 0; i < N_MAP; i++) m.put((i * 2654435761L) & 0xFFFFFFFFL, i);
            long hit = 0;
            for (long i = 0; i < N_MAP; i++) { Long v = m.get((i * 2654435761L) & 0xFFFFFFFFL); if (v != null) hit += v & 1; }
            return hit;
        });

        final int N_SORT = 5_000_000;
        run("sort_int64", N_SORT, () -> {
            SplittableRandom rng = new SplittableRandom(42); long[] v = new long[N_SORT];
            for (int i = 0; i < N_SORT; i++) v[i] = rng.nextLong() >>> 1;
            Arrays.sort(v);
            return v[N_SORT / 2] % 1000000;
        });

        final int N_OBJ = 10_000_000;
        run("alloc_small_objects", N_OBJ, () -> {
            ArrayList<Pt> v = new ArrayList<>(N_OBJ);
            for (int i = 0; i < N_OBJ; i++) v.add(new Pt(i, i * 2.0));
            double s = 0; for (Pt p : v) s += p.x() + p.y();
            return (long) s;
        });

        final long N_LINES = 5_000_000L;
        Path lf = Paths.get(tmp, "java_lines.txt");
        run("io_write_lines", N_LINES, () -> {
            try (BufferedWriter w = Files.newBufferedWriter(lf)) {
                for (long i = 0; i < N_LINES; i++) { w.write("line "); w.write(Long.toString(i)); w.write(','); w.write(Long.toString(i * 7)); w.write('\n'); }
            } catch (IOException e) { throw new UncheckedIOException(e); }
            return N_LINES;
        });
        run("io_read_parse_lines", N_LINES, () -> {
            long sum = 0;
            try (BufferedReader r = Files.newBufferedReader(lf)) {
                String line;
                while ((line = r.readLine()) != null) { int c = line.indexOf(','); sum += Long.parseLong(line, c + 1, line.length(), 10); }
            } catch (IOException e) { throw new UncheckedIOException(e); }
            return sum;
        });

        final long MB = 512;
        Path bf = Paths.get(tmp, "java_bulk.bin");
        run("io_bulk_write(per MB)", MB, () -> {
            byte[] buf = new byte[1 << 20]; Arrays.fill(buf, (byte) 'x');
            try (OutputStream o = Files.newOutputStream(bf)) { for (long i = 0; i < MB; i++) o.write(buf); }
            catch (IOException e) { throw new UncheckedIOException(e); }
            return MB;
        });
        run("io_bulk_read(per MB)", MB, () -> {
            byte[] buf = new byte[1 << 20]; long n = 0; int r;
            try (InputStream in = Files.newInputStream(bf)) { while ((r = in.read(buf)) > 0) n += r; }
            catch (IOException e) { throw new UncheckedIOException(e); }
            return n >> 20;
        });
        Files.deleteIfExists(lf); Files.deleteIfExists(bf);
    }
}
