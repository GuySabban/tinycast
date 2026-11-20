# Web Search

A fork feature (Spotcast). Return on the **Search the Web** fallback lists up to five results from Exa
in the main launcher, between the file rows and the fallback rows. It is off by default and needs the
user's own Exa API key, set in Settings › Fallbacks › Web Search.

## Invariants

- **Typing never sends a request.** Only Return, or the Cmd-K menu's first item, on Search the Web
  sends the query. `LauncherScreen.init` reads `WebSearchCoordinator.launcherRows(for:)`, which
  touches memory only.
- **Results live in memory and are never written to disk.** Exa's terms permit display copies but not
  storage. A query searched earlier in the session shows its rows again without a request, and
  removing the key or switching the feature off forgets them.
- **The fallback is offered only when a search can be sent:** the feature is on and a key is stored.
  The key is a Keychain item in the `web-search-keys` scope, never in `UserDefaults`, a backup or
  `settings.json`.
- **Result text is untrusted.** Titles and snippets are plain text with control characters removed
  and lengths capped; only `http` and `https` links open. Nothing from a result reaches a shell or a
  model.
- **The trigger moves the selection.** `LauncherScreen.searchWeb()` selects the index where the web
  section starts and calls `scrollToFollow()`, so the first placeholder is selected as soon as it
  draws and results replace placeholders in place.

## Rows

| Row | Return | Cmd-K |
| --- | --- | --- |
| Placeholder (five while searching) | nothing | no menu |
| Result | Open in Browser | Open in Browser, Copy Link, Search Again |
| No web results | Search Again | Search Again |
| Key missing or rejected | Open Web Search Settings | the same |
| Any other failure | Try Again | the same |

## Where it lives

`Tinycast/Features/WebSearch/` holds the model, the Exa provider and session, the settings store and
section, the coordinator, the row view and its menu. The launcher seam edits are listed in
`docs/planning/FORK_LEDGER.md` under P2.6.
