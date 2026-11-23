**1Password notify: a notification opens Sill on the waiting prompt (2026-11-23, branch `1password-notify` from `sill-0.6.2`).** This is the private build for approving a Mac Studio prompt from an iPhone.

- `WindowCatalog.livePromptIDs` reads the window server once a second, with no device connected. `PromptNotifier` decides when a prompt nobody watches sends a notification, at most one per 15 s.
- Sill.app runs `~/.claude/scripts/1p-approval-page.sh`, which sends the notification through Pager. Sill holds no Pager credentials.
- The iOS build handles `sill-1p://approve` by dialing the saved Mac used last. It sends no input.
- Build the iPhone app with `PRODUCT_BUNDLE_IDENTIFIER=sh.saqoo.sill-1p DEVELOPMENT_TEAM=VCFY2GFR89 CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" INFOPLIST_KEY_CFBundleDisplayName="Sill 1P"`, so it installs beside the App Store app.
- The arming delay applies to any streamed prompt and uses the sending device's route. A pick made during a follow is queued.
- Known limit: a device kept connected in the background counts as watching, so no notification is sent.
- Verified on Mac Studio and an iPhone: with no device connected, a real prompt sent the notification, its tap connected Sill 1P, the prompt showed alone, and the tap approved it. `Tests/checks/catalog-windows`: 121 checks and 60 of 60 mutants.
