**1Password notify: a notification opens Sill on the waiting prompt (2026-11-23, branch `1password-notify` from `sill-0.6.2`).** This is the private build for approving a Mac Studio prompt from an iPhone.

- `WindowCatalog.livePromptIDs` reads the window server once a second, with no device connected. `PromptNotifier` decides when a prompt nobody watches sends a notification, at most one per 15 s.
- Sill.app posts the Darwin notification `sh.saqoo.sill.1password-prompt`. The LaunchAgent `sh.saqoo.1p-approval-page` runs the Pager script, so Sill holds no Pager credentials and its TCC grants run no home-directory script.
- The private iOS build handles `sill-1p://approve?mac=<name>` by connecting to that paired Mac, through its home row when listed. It sends no input and never ends a live session.
- Build the iPhone app with `PRODUCT_BUNDLE_IDENTIFIER=sh.saqoo.sill-1p DEVELOPMENT_TEAM=VCFY2GFR89 CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" INFOPLIST_KEY_CFBundleDisplayName="Sill 1P" INFOPLIST_FILE=Info-1P.plist`, so it installs beside the App Store app.
- The arming delay applies to any streamed prompt and uses the sending device's route. Presses and keys are judged against live prompts on every source, and again when held input is replayed. A pick made during a follow is queued.
- A prompt seen during a switch is followed when that switch ends: from connection to prompt took 2.3 s before and 0.35 s after, on the iPhone.
- Known limit: a device kept connected in the background counts as watching, so no notification is sent.
- Verified on Mac Studio and an iPhone: with no device connected, a real prompt sent the notification, its tap connected Sill 1P, the prompt showed alone, and the tap approved it. `Tests/checks/catalog-windows`: 122 checks and 61 of 61 mutants.
