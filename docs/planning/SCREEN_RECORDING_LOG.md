# Screen Recording re-ask log

`LOOK.md` section 12, row 1: does macOS re-ask about direct screen capture about monthly, as
macOS 15 did? The answer comes only from the owner's Mac, over six weeks from his first grant.
Started in Phase L step 2 (2026-11-20). Not settled until the six weeks are logged.

Add one line for every Screen Recording prompt or alert macOS shows for Spotcast, the Dev build or
the spike: the date, what was granted or captured just before, and the alert's wording.

## The owner's Mac

First grant: _not yet_. The six weeks end six weeks after it.

| Date | macOS (`sw_vers`) | App | What macOS showed | Answer | Days since the last |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## VM reference (not part of the six weeks)

What a Devin macOS VM showed in step 2, so the owner knows which alert to log. A VM is reset
between sessions, so it cannot show the monthly interval.

| Date | macOS | App | What macOS showed | Answer |
| --- | --- | --- | --- | --- |
| 2026-11-20 | 26.6.2 (25G83) | spike | On `CGRequestScreenCaptureAccess()`: "would like to record this computer's screen and audio", with Open System Settings and Deny | Open System Settings, turned on |
| 2026-11-20 | 26.6.2 (25G83) | spike | After turning it on: "may not be able to record … until it is quit", with Quit & Reopen and Later | Later |
| 2026-11-20 | 26.6.2 (25G83) | spike | On the first capture after the grant: "is requesting to bypass the system private window picker and directly access your screen and audio", with Allow and Open System Settings | Allow |

The third alert is the one to watch for: it is the direct-capture confirmation that macOS 15
began repeating. On the VM it appeared on the very first capture, not a month later.
