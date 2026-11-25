# Example `.rulebox` Workspaces

Ready-to-inspect JSON rule configurations validated by `swift test`:

| File | What It Does |
|---|---|
| [`01-downloads-cleanup.rulebox`](01-downloads-cleanup.rulebox) | Moves `.dmg`/`.pkg` installers older than 14 days to Trash and sorts archives into `Archives/[Year]` with a Purple tag. |
| [`02-pdf-invoice-filer.rulebox`](02-pdf-invoice-filer.rulebox) | Scans PDF text via `PDFKit` for `"Invoice"`, tags Green, prefixes `[Year]-[Month]_`, and files into `Invoices/[Year]`. |
| [`03-screenshot-organizer.rulebox`](03-screenshot-organizer.rulebox) | Matches macOS PNG screenshots, applies a Blue Finder tag, and groups them into `Screenshots/[Year]/[Month]`. |
