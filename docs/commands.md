# Commands

The authoritative list of check commands is `commands:` in `harness.yml`; `./scripts/check.sh` runs them in order and stops at the first failure.

| Step | Purpose | When it runs |
|---|---|---|
| lint | style / static analysis | `check.sh` |
| build | compiles | `check.sh` |
| unit | unit tests | `check.sh` |
| arch | architecture rules | `check.sh` |
| ui | UI / end-to-end tests (slow) | `check.sh --full` and `/gate` |

```
./scripts/check.sh              # lint -> build -> unit -> arch
./scripts/check.sh --full       # ... -> ui
./scripts/check.sh --only unit  # one step
```

A step with an empty command, or one that exits with code 3, is reported as SKIP. SKIP is not PASS: it goes under NOT VERIFIED in the receipt.

## Other useful commands
<!-- Project-specific: run the app, regenerate code, seed data. -->
-
