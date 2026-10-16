"""M21 (B74): extrapolate the query set to 10x and 100x from two measured scales.

For each query, the growth exponent k is fitted from the p50 at 1% scale and at 100% scale (t ~ n^k, n = 100x apart),
then projected: t(10x) = t(1x) * 10^k, t(100x) = t(1x) * 100^k. The p95 is projected with the same k.
Both inputs are hot-cache measurements, so the projections are lower bounds once the data no longer fits in RAM.

usage: python perf/extrapolate.py perf/results/baseline_1pct.csv perf/results/baseline_laptop.csv perf/results/extrapolation.csv
"""
import csv
import math
import sys


def load(path):
    with open(path, encoding='utf-8-sig') as f:
        return {r['query']: r for r in csv.DictReader(f)}


def main(small_path, big_path, out_path):
    small, big = load(small_path), load(big_path)
    rows = []
    for q in sorted(big):
        s, b, b95 = float(small[q]['p50_ms']), float(big[q]['p50_ms']), float(big[q]['p95_ms'])
        k = max(0.0, math.log(b / s) / math.log(100))
        rows.append({
            'query': q, 'name': big[q]['name'],
            'p50_ms_1pct': s, 'p50_ms_laptop': b, 'growth_exponent_k': round(k, 2),
            'p50_ms_10x': round(b * 10 ** k, 1), 'p50_ms_100x': round(b * 100 ** k, 1),
            'p95_ms_100x': round(b95 * 100 ** k, 1),
        })
    rows.sort(key=lambda r: -r['p50_ms_100x'])
    for i, r in enumerate(rows, 1):
        r['degradation_rank'] = i
    with open(out_path, 'w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    first = rows[0]
    print(f"first to degrade: {first['query']} (k={first['growth_exponent_k']}, "
          f"{first['p50_ms_laptop']} ms now, {first['p50_ms_10x']} ms at 10x, {first['p50_ms_100x']} ms at 100x)")


if __name__ == '__main__':
    main(*sys.argv[1:4])
