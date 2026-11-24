# Profiles

A profile is a stack-specific set of check commands. The core of the template never changes; profiles do.

| Profile | For |
|---|---|
| `generic` | any stack: empty commands you fill in by hand |
| `ios` | Swift / Xcode: xcodebuild build and tests, SwiftLint, a pattern-based architecture check |

## Use one
`./scripts/init.sh` asks for the profile and writes its `commands.yml` into the `commands:` block of `harness.yml`.

## Add one
1. Create `profiles/<name>/commands.yml` containing a `commands:` block with `lint`, `build`, `unit`, `arch`, `ui`.
2. Put extra scripts next to it and reference them as `./profiles/<name>/script.sh`. A script that exits with code 3 is reported as SKIP.
3. Placeholders like `__SCHEME__` are filled by custom questions in `scripts/init.sh` (see the `ios` branch).
