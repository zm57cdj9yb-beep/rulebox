# Benchmarks

All measurements below were collected from a release build (`swift build -c release`) using [`./benchmarks/run_benchmarks.sh`](run_benchmarks.sh). Reproduce locally on your Mac:

```bash
./benchmarks/run_benchmarks.sh
```

## Test Environment

| Property | Value |
|---|---|
| Machine | Apple M2, 8 GB unified memory |
| OS | macOS 27.2 |
| Swift Toolchain | Apple Swift 6.4.2 (`swift build -c release`) |
| Timing Method | Median of 5 runs for dry-run scans; wall-clock + `/usr/bin/time -l` Peak RSS for execution & undo |

## Results

| Workload | Matched / Ops | Median Time | Throughput |
|---|---:|---:|---:|
| 1,000-file folder scan + 4-rule dry-run (`Kind`, `Name`, `Extension`, `Actions` simulation) | 800 matches | **107.2 ms** | ~9,328 files/sec |
| 50 real multi-line PDFs scanned via `PDFKit` (`Contents contains "Invoice"`) | 25 matches | **33.7 ms** | ~1,484 PDFs/sec (0.67 ms/PDF) |
| Execute 100 real Finder tags + tokenized renames + subfolder sorts on disk | 100 files | **87.0 ms** | ~1,149 files/sec |
| 1-Click Undo all 100 operations (restore original path, name & Finder tags) | 100 undos | **68.4 ms** | ~1,462 undos/sec |
| Peak RSS across full benchmark suite (`/usr/bin/time -l`) | — | — | **54.3 MB** |

## App Footprint

- Signed release bundle (`build/RuleBox.app`): **2.9 MB**
- Third-party Swift package dependencies: **0** (links only Apple frameworks: `AppKit`, `SwiftUI`, `PDFKit`, `UniformTypeIdentifiers`, `Foundation`)
