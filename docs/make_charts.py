#!/usr/bin/env python3
"""Generate SVG benchmark charts for language-speed README in light and dark modes.

Reads results from bench2/results_pinned/ and bench2/results/tsql_native_docker_linux.csv.
"""

from pathlib import Path
import re
import matplotlib.pyplot as plt
import numpy as np

BASE_DIR = Path(__file__).resolve().parent.parent
PINNED_DIR = BASE_DIR / "bench2" / "results_pinned"
RESULTS_DIR = BASE_DIR / "bench2" / "results"
CHARTS_DIR = BASE_DIR / "docs" / "charts"


def parse_csv(path: Path) -> dict:
    """Parse benchmark CSV file into a dictionary of test_name -> {best_seconds, ns_per_unit, checksum, cpu_ns}."""
    data = {}
    if not path.exists():
        return data

    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("Changed database"):
                continue
            parts = [p.strip() for p in line.split(",")]
            name = parts[0]
            if len(parts) >= 4:
                try:
                    units = parts[1]
                    best_s = float(parts[2]) if parts[2] and parts[2] != "n/a" else None
                    ns = float(parts[3]) if parts[3] and parts[3] != "n/a" else None
                    checksum = parts[4] if len(parts) > 4 else None
                    cpu_ns = None
                    for extra in parts[5:]:
                        if extra.startswith("cpu_ns="):
                            cpu_ns = float(extra.split("=")[1])
                    data[name] = {
                        "units": units,
                        "best_seconds": best_s,
                        "ns_per_unit": ns,
                        "checksum": checksum,
                        "cpu_ns": cpu_ns,
                    }
                except (ValueError, IndexError):
                    pass
    return data


def load_all_data():
    cpp = parse_csv(PINNED_DIR / "cpp.csv")
    java = parse_csv(PINNED_DIR / "java.csv")
    py_numba = parse_csv(PINNED_DIR / "python_numba.csv")
    py_cython = parse_csv(PINNED_DIR / "python_cython.csv")

    tsql_w1 = parse_csv(PINNED_DIR / "tsql_native_windows_run1.csv")
    tsql_w2 = parse_csv(PINNED_DIR / "tsql_native_windows_run2.csv")
    tsql_win = {}
    for k in set(tsql_w1.keys()).union(tsql_w2.keys()):
        val1 = tsql_w1.get(k, {}).get("ns_per_unit")
        val2 = tsql_w2.get(k, {}).get("ns_per_unit")
        vals = [v for v in (val1, val2) if v is not None]
        tsql_win[k] = min(vals) if vals else None

    tsql_docker_raw = parse_csv(RESULTS_DIR / "tsql_native_docker_linux.csv")
    tsql_docker = {}
    for k, v in tsql_docker_raw.items():
        tsql_docker[k] = v.get("cpu_ns")

    return {
        "cpp": cpp,
        "java": java,
        "numba": py_numba,
        "cython": py_cython,
        "tsql_win": tsql_win,
        "tsql_docker": tsql_docker,
    }


# Color definitions
COLORS = {
    "C++ (MSVC)": "#2563EB",            # Rich Blue
    "C++ (Tuned)": "#60A5FA",           # Light Sky Blue
    "Java 21": "#EA580C",               # Orange
    "Python (Numba)": "#10B981",         # Emerald Green
    "Python (Cython)": "#8B5CF6",        # Purple
    "T-SQL (Win native)": "#DC2626",    # Red
    "T-SQL (Docker/Linux)": "#F59E0B",  # Amber
}

THEMES = {
    "light": {
        "bg": "#FFFFFF",
        "plot_bg": "#F8FAFC",
        "text": "#0F172A",
        "subtext": "#64748B",
        "grid": "#E2E8F0",
        "border": "#CBD5E1",
    },
    "dark": {
        "bg": "#0D1117",
        "plot_bg": "#161B22",
        "text": "#C9D1D9",
        "subtext": "#8B949E",
        "grid": "#30363D",
        "border": "#30363D",
    },
}


def setup_style(theme_name):
    t = THEMES[theme_name]
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["Segoe UI", "DejaVu Sans", "Helvetica Neue", "Arial"],
        "text.color": t["text"],
        "axes.labelcolor": t["text"],
        "axes.edgecolor": t["border"],
        "axes.facecolor": t["plot_bg"],
        "figure.facecolor": t["bg"],
        "xtick.color": t["text"],
        "ytick.color": t["text"],
        "grid.color": t["grid"],
        "grid.linestyle": "--",
        "grid.alpha": 0.7,
        "font.size": 11,
    })


def create_compute_chart(data, theme_name):
    setup_style(theme_name)
    t = THEMES[theme_name]

    tests = [
        ("int_lcg", "int LCG\n(mul + mod)"),
        ("int_collatz", "int Collatz\n(per step)"),
        ("float_leibniz", "float Leibniz\n(series sum)"),
        ("float_mandelbrot", "float Mandelbrot\n(per iter)"),
        ("float_sin_sqrt", "float sin+sqrt\n(trig & math)"),
    ]

    series = [
        ("C++ (MSVC)", [data["cpp"][k]["ns_per_unit"] for k, _ in tests]),
        ("Java 21", [data["java"][k]["ns_per_unit"] for k, _ in tests]),
        ("Python (Numba)", [data["numba"][k]["ns_per_unit"] for k, _ in tests]),
        ("Python (Cython)", [data["cython"][k]["ns_per_unit"] for k, _ in tests]),
        ("T-SQL (Win native)", [data["tsql_win"][k] for k, _ in tests]),
        ("T-SQL (Docker/Linux)", [data["tsql_docker"][k] for k, _ in tests]),
    ]

    x = np.arange(len(tests))
    n_series = len(series)
    width = 0.13

    fig, ax = plt.subplots(figsize=(11, 5.5), dpi=150)
    fig.patch.set_facecolor(t["bg"])
    ax.set_facecolor(t["plot_bg"])

    for i, (name, values) in enumerate(series):
        offset = (i - (n_series - 1) / 2) * width
        rects = ax.bar(x + offset, values, width, label=name, color=COLORS[name], edgecolor="none", zorder=3)
        for rect in rects:
            val = rect.get_height()
            if val is not None and not np.isnan(val):
                txt = f"{val:.2f}" if val < 10 else f"{val:.1f}"
                ax.annotate(
                    txt,
                    xy=(rect.get_x() + rect.get_width() / 2, val),
                    xytext=(0, 3),
                    textcoords="offset points",
                    ha="center",
                    va="bottom",
                    fontsize=7.5,
                    color=t["text"],
                    rotation=90 if val >= 10 else 0,
                    fontweight="bold" if "Numba" in name or "C++" in name else "normal",
                )

    ax.set_ylabel("Nanoseconds per operation (log scale, lower is faster)", fontsize=11, fontweight="semibold")
    ax.set_yscale("log")
    ax.set_ylim(0.4, 70)
    ax.set_xticks(x)
    ax.set_xticklabels([label for _, label in tests], fontsize=10.5, fontweight="medium")
    ax.grid(axis="y", zorder=0)

    ax.set_title("Compute Benchmarks: Pure Numeric Performance (ns/op)", fontsize=13, fontweight="bold", pad=15)
    ax.legend(loc="upper left", bbox_to_anchor=(0.0, 1.15), ncol=3, frameon=True,
              facecolor=t["plot_bg"], edgecolor=t["border"], fontsize=9.5)

    plt.tight_layout()
    out_file = CHARTS_DIR / f"compute_{theme_name}.svg"
    plt.savefig(out_file, format="svg", bbox_inches="tight")
    plt.close()
    print(f"Saved: {out_file}")


def create_io_memory_chart(data, theme_name):
    setup_style(theme_name)
    t = THEMES[theme_name]

    test_keys = [
        "string_format_parse",
        "hashmap_insert_lookup",
        "sort_int64",
        "io_write_lines",
        "io_read_parse_lines",
    ]
    test_labels = [
        "String\nformat+parse",
        "Hash Map\ninsert+lookup",
        "Sort\n5M int64",
        "Write lines /\nDurable rows",
        "Read+parse lines /\nRows (bulk/scan)",
    ]

    # Map T-SQL keys:
    # write lines -> rows_write_durable
    # read lines -> io_read_parse_lines(BULK INSERT) / rows_read_parse
    cpp_std = [data["cpp"][k]["ns_per_unit"] for k in test_keys]
    cpp_tuned = [
        data["cpp"].get(f"{k}[tuned]", {}).get("ns_per_unit") for k in test_keys
    ]
    java_vals = [data["java"].get(k, {}).get("ns_per_unit") for k in test_keys]
    numba_vals = [data["numba"].get(k, {}).get("ns_per_unit") for k in test_keys]
    cython_vals = [data["cython"].get(k, {}).get("ns_per_unit") for k in test_keys]

    tsql_win_vals = [
        data["tsql_win"].get("string_format_parse"),
        data["tsql_win"].get("hashmap_insert_lookup"),
        None,  # sort
        data["tsql_win"].get("rows_write_durable"),
        data["tsql_win"].get("io_read_parse_lines(BULK INSERT)"),  # 260 ns
    ]
    tsql_docker_vals = [
        data["tsql_docker"].get("string_format_parse"),
        data["tsql_docker"].get("hashmap_insert_lookup"),
        None,  # sort
        data["tsql_docker"].get("rows_write_durable"),
        data["tsql_docker"].get("rows_read_parse"),
    ]

    series = [
        ("C++ (MSVC)", cpp_std),
        ("C++ (Tuned)", cpp_tuned),
        ("Java 21", java_vals),
        ("Python (Numba)", numba_vals),
        ("Python (Cython)", cython_vals),
        ("T-SQL (Win native)", tsql_win_vals),
        ("T-SQL (Docker/Linux)", tsql_docker_vals),
    ]

    x = np.arange(len(test_labels))
    n_series = len(series)
    width = 0.11

    fig, ax = plt.subplots(figsize=(12, 5.8), dpi=150)
    fig.patch.set_facecolor(t["bg"])
    ax.set_facecolor(t["plot_bg"])

    for i, (name, values) in enumerate(series):
        offset = (i - (n_series - 1) / 2) * width
        plot_vals = [v if (v is not None and not np.isnan(v)) else 0.0 for v in values]
        rects = ax.bar(x + offset, plot_vals, width, label=name, color=COLORS[name], edgecolor="none", zorder=3)
        for idx, rect in enumerate(rects):
            val = values[idx]
            if val is not None and not np.isnan(val) and val > 0:
                txt = f"{val:.0f}" if val >= 10 else f"{val:.1f}"
                ax.annotate(
                    txt,
                    xy=(rect.get_x() + rect.get_width() / 2, val),
                    xytext=(0, 3),
                    textcoords="offset points",
                    ha="center",
                    va="bottom",
                    fontsize=7,
                    color=t["text"],
                    rotation=90 if val >= 100 else 0,
                    fontweight="bold" if "Tuned" in name or "Java" in name else "normal",
                )
            elif val is None or np.isnan(val):
                # Annotate N/A
                ax.annotate(
                    "n/a",
                    xy=(rect.get_x() + rect.get_width() / 2, 8),
                    textcoords="offset points",
                    xytext=(0, 0),
                    ha="center",
                    va="bottom",
                    fontsize=6.5,
                    color=t["subtext"],
                    fontstyle="italic",
                )

    ax.set_ylabel("Nanoseconds per operation (log scale, lower is faster)", fontsize=11, fontweight="semibold")
    ax.set_yscale("log")
    ax.set_ylim(8, 2000)
    ax.set_xticks(x)
    ax.set_xticklabels(test_labels, fontsize=10, fontweight="medium")
    ax.grid(axis="y", zorder=0)

    ax.set_title("Data Structures, Strings, Sorting & I/O Performance (ns/op)", fontsize=13, fontweight="bold", pad=15)
    ax.legend(loc="upper left", bbox_to_anchor=(0.0, 1.15), ncol=4, frameon=True,
              facecolor=t["plot_bg"], edgecolor=t["border"], fontsize=9)

    plt.tight_layout()
    out_file = CHARTS_DIR / f"io_memory_{theme_name}.svg"
    plt.savefig(out_file, format="svg", bbox_inches="tight")
    plt.close()
    print(f"Saved: {out_file}")


def create_tsql_comparison_chart(data, theme_name):
    setup_style(theme_name)
    t = THEMES[theme_name]

    items = [
        ("int_lcg", "LCG (mul+mod)", data["tsql_win"].get("int_lcg"), data["tsql_docker"].get("int_lcg")),
        ("int_collatz", "Collatz (/step)", data["tsql_win"].get("int_collatz"), data["tsql_docker"].get("int_collatz")),
        ("float_leibniz", "Leibniz (pi)", data["tsql_win"].get("float_leibniz"), data["tsql_docker"].get("float_leibniz")),
        ("float_mandelbrot", "Mandelbrot (/iter)", data["tsql_win"].get("float_mandelbrot"), data["tsql_docker"].get("float_mandelbrot")),
        ("float_sin_sqrt", "sin + sqrt", data["tsql_win"].get("float_sin_sqrt"), data["tsql_docker"].get("float_sin_sqrt")),
        ("string_format_parse", "String fmt/parse", data["tsql_win"].get("string_format_parse"), data["tsql_docker"].get("string_format_parse")),
        ("hashmap_insert_lookup", "Hashmap (memory-opt)", data["tsql_win"].get("hashmap_insert_lookup"), data["tsql_docker"].get("hashmap_insert_lookup")),
        ("rows_write_durable", "Durable rows write", data["tsql_win"].get("rows_write_durable"), data["tsql_docker"].get("rows_write_durable")),
        ("rows_read_parse", "Rows read/parse", data["tsql_win"].get("rows_read_parse"), data["tsql_docker"].get("rows_read_parse")),
    ]

    labels = [item[1] for item in items]
    win_vals = [item[2] for item in items]
    docker_vals = [item[3] for item in items]

    x = np.arange(len(labels))
    width = 0.35

    fig, ax = plt.subplots(figsize=(11, 5.5), dpi=150)
    fig.patch.set_facecolor(t["bg"])
    ax.set_facecolor(t["plot_bg"])

    rects1 = ax.bar(x - width / 2, win_vals, width, label="SQL Server 2025 RTM (Windows Native)", color=COLORS["T-SQL (Win native)"], zorder=3)
    rects2 = ax.bar(x + width / 2, docker_vals, width, label="SQL Server 2025 CU9 (Docker Linux WSL2)", color=COLORS["T-SQL (Docker/Linux)"], zorder=3)

    for i in range(len(labels)):
        w = win_vals[i]
        d = docker_vals[i]
        diff_pct = ((d - w) / w) * 100
        diff_txt = f"{diff_pct:+.0f}%" if abs(diff_pct) >= 1 else "0%"

        ax.annotate(
            f"{w:.1f}",
            xy=(rects1[i].get_x() + rects1[i].get_width() / 2, w),
            xytext=(0, 3),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=8,
            color=t["text"],
            fontweight="bold",
        )
        ax.annotate(
            f"{d:.1f}\n({diff_txt})",
            xy=(rects2[i].get_x() + rects2[i].get_width() / 2, d),
            xytext=(0, 3),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=7.5,
            color=COLORS["T-SQL (Docker/Linux)"] if theme_name == "light" else "#FBBF24",
            fontweight="semibold",
        )

    ax.set_ylabel("CPU Nanoseconds per operation (log scale, lower is faster)", fontsize=11, fontweight="semibold")
    ax.set_yscale("log")
    ax.set_ylim(1.2, 2200)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=25, ha="right", fontsize=9.5, fontweight="medium")
    ax.grid(axis="y", zorder=0)

    ax.set_title("Natively Compiled T-SQL: Windows Native (RTM) vs Docker Linux (CU9)", fontsize=13, fontweight="bold", pad=15)
    ax.legend(loc="upper left", frameon=True, facecolor=t["plot_bg"], edgecolor=t["border"], fontsize=9.5)

    plt.tight_layout()
    out_file = CHARTS_DIR / f"tsql_comparison_{theme_name}.svg"
    plt.savefig(out_file, format="svg", bbox_inches="tight")
    plt.close()
    print(f"Saved: {out_file}")


def main():
    data = load_all_data()
    CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    for theme in ("light", "dark"):
        create_compute_chart(data, theme)
        create_io_memory_chart(data, theme)
        create_tsql_comparison_chart(data, theme)
    print("All charts generated successfully.")


if __name__ == "__main__":
    main()
