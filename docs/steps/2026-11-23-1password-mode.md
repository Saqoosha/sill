**1Password mode: a connected device follows approval prompts (2026-11-23, branch `1password-mode` from v0.6.2 at 4e00c80).** The fork's PR targets `sill-0.6.2` because upstream `main` was 46 commits ahead and conflicted.

- `CatalogWindows.isOnePasswordPrompt` matches the panel's shape: layer 101, 300–600 × 200–600 pt (measured 400 × 325 and 400 × 346 on 1Password 8.12.44). `WindowCatalog` lists it only when the owner passes a code-signing check for team 2BUA8C4S2C.
- `CatalogWindows.PromptFollow` holds the decisions: follow, retry, next prompt, the way back, a person's pick, and the 0.75 s after a prompt shows when presses are dropped. A Desktop pick within 3 s of a follow counts as the device's automatic request.
- The prompt streams where it is: no virtual display, resize or app activation.
- Known limit: following a prompt sends a window on the virtual display home, so a full-screen window there comes back staged but not full screen.
- Verified: `Tests/checks/run-all.sh` and the catalog-windows mutants (49 of 49). On Mac Studio with an iPhone, real prompts were approved from the Desktop and from a window on the virtual display, and each stream returned to its source.
