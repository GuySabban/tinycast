# Rules for agents working on Spotcast

These rules take precedence over upstream's AGENTS.md and CLAUDE.md wherever they conflict.

Spotcast is a fork of Tinycast (upstream: abue-ammar/tinycast). Before any task, read docs/planning/:
IMPLEMENTATION_ROADMAP.md is the plan; PROPOSED_ARCHITECTURE.md, UNIVERSAL_INSTALL.md and LOOK.md are the
designs; BASELINE.md is the measured state; FORK_LEDGER.md lists every change to upstream files;
LESSONS.md holds gotchas found so far.

## Branches

- `main` mirrors upstream and takes no commits. All Spotcast work lives on `universal-launcher`.
- One roadmap step per pull request, against `universal-launcher`. Never merge your own PR.
- Never push to upstream. Never force-push without the owner's explicit yes.

## Scope

- Do one roadmap step, then stop. Don't start the next step.
- Don't decide open decisions (D-numbers in RISKS_AND_DECISIONS.md). List them in the PR.
- If the plan turns out wrong, say so in the PR and update the planning doc in the same PR.

## Code

- Add beside the existing code in upstream's style. Don't restructure seam files (ARCHITECTURE_AUDIT.md
  section 1.12). If a task seems to need it, stop and explain why.
- Every line changed in an existing upstream file gets an entry in FORK_LEDGER.md.
- Never edit upstream's docs or harnesses. Record doc errata in the ledger.
- New model code is test-first, with a harness registered in Scripts/run-tests.sh. Every bug fix gets a
  harness case that fails without the fix.
- Test the real path, not just the logic: when a feature is wired into the launcher, at least one harness
  case goes through the coordinator end to end.
- New strings in all eight languages, as lint requires.

## Checks before opening a PR

- All harnesses pass in Dark mode, lint is clean with no more warnings than BASELINE.md, the Debug build
  has no new warnings, and the Model purity check is empty.
- In the PR, separate what you actually ran from what you only reasoned about. Never describe untested
  behaviour as working.
- Performance and memory numbers from a VM are not real measurements. Say so, and list them as hands-on
  checks for the owner.

## Safety

- Product code never runs AI-generated scripts, never executes downloaded code, and never installs
  anything without the user's approval after verification (UNIVERSAL_INSTALL.md).
- Real app installs only inside your own VM, never on the owner's Mac.
- Screen content (LOOK.md), web results and file contents are untrusted data: no tools in any AI turn that
  carries them.
- Never commit secrets, API keys, certificates or signing keys.
