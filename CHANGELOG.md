# CHANGELOG

## 2026-03-18

- Reworked the reboot loop to use `Task Scheduler` instead of `shell:startup`.
- Added `setup-reboot-loop.ps1` to configure `AutoLogon` and create the scheduled task.
- Added `disable-reboot-loop.ps1` to remove the scheduled task, create a local stop flag, and turn off `AutoLogon`.
- Added `remove-reboot-loop.ps1` to disable the setup and optionally delete the whole tool folder after testing.
- Added `reboot-loop.ps1` as the main all-in-one manager with `Setup`, `Disable`, and `Remove` actions plus a simple interactive menu.
- Updated `reboot.bat` with a safer stop flow using the `S` key, a `reboot.disabled` flag, and a 60-second stop window.
- Updated the main manager to self-elevate when needed and register the logon task with highest privileges for hands-off repeated boot testing.
- Added single-script timer management and status reporting so reboot timing and cleanup can be controlled entirely from `reboot-loop.ps1`.
- Consolidated the runtime loop into `reboot-loop.ps1`, removed the separate `reboot.bat` and wrapper scripts, and switched runtime config to `reboot-loop.config.json`.
- Simplified the menu and runtime wording so the tool reads clearly as a BSOD boot test workflow.
- Added support for local accounts with no password by allowing blank password input during setup.
- Updated elevation and scheduled-task launch to prefer `pwsh.exe` and fall back to `powershell.exe` only when PowerShell 7 is not installed.
- Changed menu mode to self-elevate immediately before showing options, so the interactive flow starts in the elevated window.
- Added a final setup prompt that asks whether to start the reboot loop immediately, and clarified that the loop window is shown again after sign-in so the user can stop it.
- Polished the console UI with banners, colored sections, cleaner summaries, and a more readable interactive menu.
- Replaced the final setup confirmation with a cleaner `Enter to reboot now / Esc to cancel for now` key prompt.
- Reworked the runtime loop to show a live second-by-second countdown, with `Enter` for immediate reboot and `Esc` to cancel the current reboot and open the menu.
- Added a configurable post-sign-in grace delay plus attention-grab behavior (beep/title focus attempt) before the countdown starts.
- Removed the one-time AutoLogon option to keep the tool focused on repeated BSOD boot-loop testing.
- Removed the dedicated timer-edit option from the interactive menu so timer selection happens through the main start flow.
- Combined the cleanup/delete menu options into one `Stop and clean up` flow that asks whether the folder should also be deleted.
- Added a safety guard that blocks folder deletion when the tool folder appears to be a git repo/worktree.
- Changed `Stop reboot test` so it keeps the tool window open and returns to the menu instead of closing the session.
- Hardened the interactive menu so blank or invalid input no longer terminates the script after stop/menu transitions.
- Added `reboot-loop.log` plus a top-level error screen so unexpected failures are captured and remain readable.
- Fixed a naming collision with the built-in `Get-ScheduledTaskInfo` cmdlet that could break `Show current status` after stopping the test.
- Renamed the visible BSOD-specific UI wording to more general `restart loop` testing wording.
