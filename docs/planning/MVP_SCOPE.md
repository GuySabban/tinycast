# MVP scope

The smallest build that shows what this launcher is for and that is worth using every day.

Design is in `PROPOSED_ARCHITECTURE.md`, the work plan in `IMPLEMENTATION_ROADMAP.md`, and risks and
open decisions in `RISKS_AND_DECISIONS.md`.

## The MVP in one sentence

Upstream Tinycast under its own identity, with the shell fallback gated, the keyless AI route set up,
and one new capability: installing a Mac app from the main list by typing its name.

## The demo flow

Type `install blender` and press Return twice.

1. The first row is an install card for the Homebrew cask `blender`.
2. Return fetches the cask's details and shows an approval dialog with the app's name and version,
   where it comes from, the exact command that will run, and where it will be installed.
3. Return again starts the install. A window streams Homebrew's output and offers Stop.
4. When it finishes, the launcher checks the result and confirms it.
5. Open the launcher and type `blender`. The app is there to launch.

No browser, no download page, no drag to Applications, and nothing ran that was not shown first.

## In scope

| Area | What the MVP includes |
| --- | --- |
| Identity | The fork's own name, bundle identifier and URL scheme, so the built-in updater cannot replace it with upstream's app |
| Safety fix | Run Shell Command offered only when Custom Commands is on, and asking before it runs |
| Install: entry | `install NAME` typed in the main list, matched against Homebrew's cask names without a network call per keystroke |
| Install: approval | One dialog showing name, version, source, the exact command and the install location |
| Install: run | `brew install --cask` with streamed output and Stop |
| Install: checks | Already installed (by Homebrew or otherwise), disabled by Homebrew, Homebrew missing, password needed |
| Install: hand-off | Homebrew setup and password casks shown as a command with a button that opens Terminal |
| Install: after | Verification, an application rescan and a confirmation |
| Settings | An install switch, as a section in the Applications pane |
| AI | Upstream's AI as it is, configured on the owner's Mac for the Claude CLI |
| Everything else | All upstream features kept and still merged from upstream |

App and file search (feature A) and AI answers on the same panel (feature C) are in the MVP because
upstream already ships them. The MVP adds no code to either.

## Why feature D is in, and what stands in its way

No technical blocker was found for a Homebrew-cask version. The pieces exist and are callable as they
are: a streamed shell runner, an output window, a multi-button dialog, an application rescan and a
signature check.

Three limits shape the version that fits the MVP:

| Limit | Consequence for the MVP |
| --- | --- |
| The shell runner's input is closed, so a password prompt cannot be answered in the app | Casks that need a password are handed to Terminal. They are recognisable in advance from the cask record. |
| Cask records carry no bundle identifier | "Already installed" is decided from Homebrew's own install record and the app's file name |
| The full cask catalogue is 19 MB | Matching uses Homebrew's 64 KB install-count file, which lists tokens, not display names. Details are fetched once, on Return. |

## Deferred

In the order they are planned (phases in `IMPLEMENTATION_ROADMAP.md`):

1. **Web result rows in the main list** (feature B). Needs an API key and a new network feature.
2. **Search refinements** (feature A): usage ranking and aliases for files.
3. **Install refinements**: display names and descriptions on the card, alternates as rows, formulae,
   upgrade and uninstall through Homebrew, adopting an app installed by hand.
4. **Context actions** on files, images and clipboard items (feature E).
5. **Natural-language OS actions** through a typed action set (feature F).
6. **AI answers as rows in the main list** (the later phase of feature C). This is the hard-fork
   checkpoint.
7. **In-app updates for the fork.** Until then friends install a new build by hand.

## Non-goals

- Installing Homebrew for the user, or answering a password prompt inside the app.
- Installing anything that is not a Homebrew cask.
- AI-written install commands or download scripts, in any phase.
- Restructuring a seam file, or replacing upstream's row, command or action types.
- Removing upstream features. Unused ones are switched off in Settings.
- Accounts, analytics, a backend, or a plugin framework.
- Support for Intel Macs or for macOS before 26.

## Definition of done

The MVP is done when every line below is true on the owner's Mac.

**Phase 0 is closed**

- The Debug build compiles with no new warnings, and the harnesses and lint pass on the fork's branch.
- A Release build reports the fork's bundle identifier. The launcher lists no Check for Updates
  command, and the menu-bar item of that name only says this is a local build. No update is offered.
- With default settings, a query that matches nothing no longer offers Run Shell Command.
- A trial merge of upstream `main` into a scratch branch has been done once and its conflicts noted.

**Install works**

- `install blender` shows the install card as the first row.
- Return shows the approval dialog within about a second on a normal connection.
- The dialog's command line is character-for-character what runs.
- After approval, the app is installed, the three verification checks pass, and typing the app's name
  finds it without restarting the launcher.
- A cask that needs a password is never started in the app, and the Terminal button works.
- With Homebrew absent, the dialog shows the setup command from brew.sh and nothing is installed.
- An app that is already present is offered for opening, not reinstalled.
- A cask Homebrew has disabled is refused with Homebrew's reason.
- Cancelling at any point leaves nothing running.

**Quality**

- New model and store code has harnesses in upstream's style, registered in `Scripts/run-tests.sh`.
- Every new string is translated in the eight languages lint requires.
- Resident memory stays under 100 MB at the four points upstream's pull-request template names.
- The lines changed in existing files are within a fifth of the seam budget in
  `PROPOSED_ARCHITECTURE.md` section 7.
- Upstream's newest stable tag still merges, with conflicts only where the seam budget predicts them.

**Before a build goes to a friend**

- Every item of the friend-build gate in `IMPLEMENTATION_ROADMAP.md` is done.
