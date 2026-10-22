// Benchmark suite v2 - Java (HotSpot JIT; best of 3, earlier runs act as warm-up).
import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.function.LongSupplier;

public class Bench {
    static void run(String name, long units, LongSupplier f) {
        double best = 1e99; long chk = 0;
        for (int r = 0; r < 3; r++) { long t0 = System.nanoTime(); chk = f.getAsLong(); best = Math.min(best, (System.nanoTime() - t0) / 1e9); }
        System.out.printf(Locale.ROOT, "%s,%d,%.4f,%.3f,%d%n", name, units, best, best * 1e9 / units, chk);
    }
    static final long M31 = 2147483648L;

    static long mandel(int W, int H, int MAXI) {
        long total = 0;
        for (int py = 0; py < H; py++) {
            double ci = -1.25 + 2.5 * py / H;
            for (int px = 0; px < W; px++) {
                double cr = -2.0 + 2.5 * px / W, zr = 0, zi = 0; int it = 0;
                while (it < MAXI && zr * zr + zi * zi <= 4.0) { double t = zr * zr - zi * zi + cr; zi = 2.0 * zr * zi + ci; zr = t; it++; }
                total += it;
            }
        }
        return total;
    }

    public static void main(String[] a) throws Exception {
        String tmp = a.length > 0 ? a[0] : ".";

        final long N_LCG = 100_000_000L;
        run("int_lcg", N_LCG, () -> {
            long x = 88172645, acc = 0;
            for (long i = 0; i < N_LCG; i++) { x = (x * 1103515245L + 12345) % M31; acc += x % 65536; }
            return acc;
        });

        final long N_COL = 1_000_000L, COL_STEPS = 131434424L;
        run("int_collatz", COL_STEPS, () -> {
            long steps = 0;
            for (long n = 1; n <= N_COL; n++) { long v = n; while (v != 1) { v = (v % 2 == 1) ? 3 * v + 1 : v / 2; steps++; } }
            return steps;
        });

        final long N_LEIB = 100_000_000L;
        run("float_leibniz", N_LEIB, () -> {
            double s = 0, sign = 1;
            for (long k = 0; k < N_LEIB; k++) { s += sign / (2.0 * k + 1.0); sign = -sign; }
            return (long) (s * 4e9);
        });

        long iters = mandel(1000, 1000, 200);
        run("float_mandelbrot", iters, () -> mandel(1000, 1000, 200));

        final long N_MATH = 20_000_000L;
        run("float_sin_sqrt", N_MATH, () -> {
            double s = 0;
            for (long i = 0; i < N_MATH; i++) s += Math.sin(i * 0.001) * Math.sqrt((double) i);
            return (long) s;
        });

        final long N_STR = 5_000_000L;
        run("string_format_parse", N_STR, () -> {
            long acc = 0;
            for (long i = 0; i < N_STR; i++) {
                String s = "line " + i + "," + (i * 7);
                int p = s.indexOf(',');
                acc += Long.parseLong(s.substring(p + 1)) + s.length();
            }
            return acc;
        });

        final int N_MAP = 5_000_000;
        run("hashmap_insert_lookup", N_MAP, () -> {
            HashMap<Long, Long> m = new HashMap<>(N_MAP * 2);
            for (long i = 0; i < N_MAP; i++) m.put((i * 2654435761L) % 4294967296L, i);
            long hit = 0;
            for (long i = 0; i < N_MAP; i++) { Long v = m.get((i * 2654435761L) % 4294967296L); if (v != null) hit += v % 2; }
            return hit;
        });

        final int N_SORT = 5_000_000;
        run("sort_int64", N_SORT, () -> {
            long[] v = new long[N_SORT]; long x = 88172645;
            for (int i = 0; i < N_SORT; i++) { x = (x * 1103515245L + 12345) % M31; v[i] = x; }
            Arrays.sort(v);
            return v[0] + v[N_SORT / 2] + v[N_SORT - 1];
        });

        final long N_LINES = 5_000_000L;
        Path lf = Paths.get(tmp, "java2_lines.txt");
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
        Files.deleteIfExists(lf);
    }
}
