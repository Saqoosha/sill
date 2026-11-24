**1Password notify delay: approving at the Mac sends nothing (2026-11-24, branch `1password-notify-delay` from `sill-0.6.2`).** The notification went out the moment a prompt appeared, so a prompt approved at the Mac still buzzed the iPhone.

- `PromptNotifier` sends only for a prompt that has been open 20 s (`delay`). 1Password closes a prompt after 60 s, and Sill cannot change that, so about 40 s are left to approve from the iPhone. Noah chose 20 s over 30 s and 45 s.
- A prompt that closed after 55 s or more (`timedOutAge`) timed out unanswered. The next prompt within 5 minutes (`missedWindow`) is sent at once. A prompt that closed sooner was approved, which ends that.
- The 15 s gap between notifications is gone: with the delay, a later prompt always waits longer than it, and one notification still covers every prompt open when it is sent.
- Verified on Mac Studio and the iPhone: one prompt notified 21 s after it opened; a prompt left to time out, then a second one notified about 1 s after it opened, approved from the iPhone. `Tests/checks/catalog-windows`: 156 checks and 85 of 85 mutants.
