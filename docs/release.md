# Release rules

Releasing is a **human-only** action. The agent prepares; the human executes.

## What the agent may prepare
- release notes draft, version bump proposal, changelog entry;
- the list of checks that passed on the release candidate;
- the exact commands the human will run.

## What the agent never does
- upload to App Store Connect / TestFlight, publish packages, create release tags on remotes;
- run database or schema migrations, apply infrastructure changes;
- touch signing identities, certificates, tokens.

## Release checklist (human)
<!-- Fill in per project. -->
- [ ] receipt of the final task is ACCEPTED and read
- [ ] full checks (`./scripts/check.sh --full`) green on the release commit
- [ ] migrations reviewed, rollback known
-
