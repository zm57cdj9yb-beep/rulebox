#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
RAM_GB="$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))"
OS_VER="$(sw_vers -productVersion 2>/dev/null || uname -sr)"
SWIFT_VER="$(swift --version 2>&1 | head -n 1)"

echo "=== Machine & Toolchain ==="
echo "CPU:   $CPU_BRAND"
echo "RAM:   ${RAM_GB} GB"
echo "OS:    macOS $OS_VER"
echo "Swift: $SWIFT_VER"

echo ""
echo "=== Building RuleBoxBench (release) ==="
swift build -c release --product RuleBoxBench >/dev/null

echo ""
echo "=== Running Benchmarks (with /usr/bin/time -l Peak RSS) ==="
TMP_TIME="$(mktemp)"
trap 'rm -f "$TMP_TIME"' EXIT
/usr/bin/time -l "$ROOT_DIR/.build/release/RuleBoxBench" 2>"$TMP_TIME"
RSS_BYTES="$(awk '/maximum resident set size/ {print $1}' "$TMP_TIME")"
echo "bench|peak_rss_bytes|${RSS_BYTES}"
