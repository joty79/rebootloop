# PROJECT_RULES

## Decisions

### 2026-03-18 - Reboot loop setup moved from Startup folder to Task Scheduler

- Date: 2026-03-18
- Problem: The reboot loop depended on `shell:startup`, which only runs after Explorer/logon and is awkward to stop safely once automatic sign-in is enabled.
- Root cause: Startup folder launch is tied to the shell instead of a dedicated automation entry point, so repeated reboot testing becomes brittle.
- Guardrail/rule: Use `Task Scheduler` as the source of truth for relaunching `reboot.bat` at logon. Keep a local `reboot.disabled` flag plus dedicated disable/remove scripts so the loop can be paused, uninstalled, and cleaned off a client PC after testing.
- Files affected: `reboot.bat`, `setup-reboot-loop.ps1`, `disable-reboot-loop.ps1`, `remove-reboot-loop.ps1`
- Validation/tests run: PowerShell parser validation for all `.ps1` files and manual review of task-registration, cleanup flow, and `Winlogon` registry paths.

### 2026-03-18 - Single entrypoint preferred for field use

- Date: 2026-03-18
- Problem: Separate setup, disable, and remove scripts are easy to forget or mix up on a client machine during quick BSOD testing.
- Root cause: The operator workflow was split across multiple script names even though all actions belong to the same temporary tool.
- Guardrail/rule: Keep one primary management script for field use. Extra scripts may stay only as thin compatibility wrappers that forward into the main entrypoint.
- Files affected: `reboot-loop.ps1`, `setup-reboot-loop.ps1`, `disable-reboot-loop.ps1`, `remove-reboot-loop.ps1`, `README.md`
- Validation/tests run: PowerShell parser validation and manual review of wrapper forwarding behavior.

### 2026-03-18 - First run may elevate, later boots must stay hands-off

- Date: 2026-03-18
- Problem: The reboot test must continue through repeated boots without any extra operator input after the first setup pass.
- Root cause: Admin-only setup steps (`AutoLogon`, task registration, final file cleanup) can interrupt the flow if the script expects the operator to relaunch it manually as Administrator later.
- Guardrail/rule: The main manager should self-elevate for setup and full removal when needed, and the scheduled task should run with highest privileges so later logons do not require further human interaction. The reboot window must always allow a generous manual stop window before the next reboot.
- Files affected: `reboot-loop.ps1`, `reboot.bat`, `README.md`
- Validation/tests run: PowerShell parser validation and manual review of self-elevation, scheduled-task principal, and stop-timer behavior.

### 2026-03-18 - Operator controls stay inside the main manager

- Date: 2026-03-18
- Problem: Field use is error-prone when the operator must edit files manually or remember multiple one-off commands just to change timers or inspect state.
- Root cause: Runtime settings originally lived in script code instead of a manager-owned config flow.
- Guardrail/rule: Keep timer changes, status checks, disable, remove, and cleanup under `reboot-loop.ps1`. Persist runtime timing values in a manager-owned config file that `reboot.bat` reads automatically.
- Files affected: `reboot-loop.ps1`, `reboot.bat`, `README.md`
- Validation/tests run: PowerShell parser validation and manual review of config read/write behavior.

### 2026-03-18 - One file is the source of truth

- Date: 2026-03-18
- Problem: Even with an all-in-one manager, a separate runtime script still leaves room for drift and operator confusion.
- Root cause: The reboot cycle logic remained in `reboot.bat` while management lived in `reboot-loop.ps1`.
- Guardrail/rule: Keep both management and runtime loop logic in `reboot-loop.ps1`. The scheduled task should call the same script with an internal loop action, and helper wrappers should be removed once they are no longer needed.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of scheduled-task action arguments and loop behavior.

### 2026-03-18 - Local no-password accounts are valid test targets

- Date: 2026-03-18
- Problem: Field testing can happen on local accounts that intentionally have no password, and setup should not fail in that case.
- Root cause: The first implementation treated empty password input as an error even for local-account console logon scenarios.
- Guardrail/rule: During setup, allow empty password input for local accounts and configure AutoLogon with an empty password when the operator leaves the prompt blank.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of setup flow for blank-password local accounts.

### 2026-03-18 - Prefer PowerShell 7 for relaunch and scheduled runtime

- Date: 2026-03-18
- Problem: Launching with `powershell.exe` can unexpectedly switch the operator from PowerShell 7 into Windows PowerShell 5.1.
- Root cause: Elevation and scheduled-task registration originally hard-coded `powershell.exe`.
- Guardrail/rule: Prefer `pwsh.exe` whenever it is installed. Fall back to `powershell.exe` only if PowerShell 7 is unavailable.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of launcher selection for self-elevation and scheduled-task registration.

### 2026-03-18 - Interactive menu should elevate before it starts

- Date: 2026-03-18
- Problem: Opening the menu first and elevating later is awkward because the operator starts in one console and then gets redirected into another mid-flow.
- Root cause: Elevation originally happened lazily only when a privileged action was chosen.
- Guardrail/rule: When the script is launched in interactive menu mode, elevate immediately before showing the menu so the whole operator flow happens in the final console window.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of menu-mode relaunch behavior.

### 2026-03-18 - Setup must end with an explicit start-now decision

- Date: 2026-03-18
- Problem: Finishing setup without a clear "start now or later" prompt leaves the operator unsure whether the test is already running.
- Root cause: Setup previously ended after registration without a final operator confirmation step.
- Guardrail/rule: End setup with a clear prompt asking whether to start the reboot loop immediately. Also explain that the loop window will appear after sign-in because visibility is required for the manual stop path.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of post-setup control flow.

### 2026-03-18 - Runtime loop must show live countdown and menu escape path

- Date: 2026-03-18
- Problem: A static wait prompt makes it hard to judge how much time remains before the next reboot.
- Root cause: The runtime loop originally relied on `choice.exe` instead of a custom countdown display.
- Guardrail/rule: During the active reboot loop, show a live second-by-second countdown. Use `Enter` for immediate reboot and `Esc` to cancel the current reboot and open the management menu.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of countdown, key handling, and menu re-entry flow.

### 2026-03-18 - Sign-in should get a short settle delay and attention grab

- Date: 2026-03-18
- Problem: Right after sign-in, the countdown window may appear without being obvious or immediately focused.
- Root cause: Explorer and startup activity can compete with the test window during the first seconds after logon.
- Guardrail/rule: Before the reboot countdown starts, wait a short configurable sign-in grace delay and make a best-effort focus/attention grab using beeps, title flash, and foreground activation attempts.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of grace-delay and attention-grab flow.

### 2026-03-18 - Cleanup menu stays single-step

- Date: 2026-03-18
- Problem: Separate menu entries for cleanup and cleanup-plus-delete create unnecessary hesitation in the field.
- Root cause: The operator had to decide between two similar cleanup paths before even starting the teardown flow.
- Guardrail/rule: Keep one interactive cleanup entry. After cleanup completes, ask whether the folder should also be deleted instead of splitting that choice into a separate menu item.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of merged cleanup prompt flow.

### 2026-03-18 - Never auto-delete the tool folder when it is a git repo

- Date: 2026-03-18
- Problem: Once the tool folder becomes a git repo/worktree, an interactive cleanup delete option could accidentally remove source-controlled project content.
- Root cause: The delete-folder cleanup path only considered temporary field-use folders, not repo-owned workspaces.
- Guardrail/rule: If the tool folder contains `.git`, block automatic folder deletion and keep the repo on disk even when the operator asked to remove the folder.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of git-repo deletion guard behavior.

### 2026-03-18 - Stop action must keep the operator inside the tool

- Date: 2026-03-18
- Problem: Using `Stop reboot test` closed the interactive session immediately, which made the stop flow feel abrupt and forced the operator to relaunch the tool for the next action.
- Root cause: The menu session treated `Disable` like a terminal action and returned right after executing it.
- Guardrail/rule: `Stop reboot test` should stop the loop but keep the current window alive and return the operator to the main menu.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of post-stop menu flow.

### 2026-03-18 - Interactive menu must survive blank input after stop flow

- Date: 2026-03-18
- Problem: After `Stop reboot test`, choosing another menu option could terminate the script as if it had crashed.
- Root cause: The menu used terminating errors for invalid input, and the stop-to-menu transition could leave a blank selection that was treated as fatal.
- Guardrail/rule: Menu selection must loop on blank or invalid input and show a warning instead of throwing a terminating error.
- Files affected: `reboot-loop.ps1`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of menu re-entry behavior after stop.

### 2026-03-18 - Unexpected errors must leave a readable log

- Date: 2026-03-18
- Problem: When the tool failed, red error text could flash and the operator had no reliable record of what happened.
- Root cause: There was no top-level crash logger or final error screen.
- Guardrail/rule: Wrap the main entry flow in a top-level `try/catch`, write unexpected errors to `reboot-loop.log`, and show the log path on screen before exit.
- Files affected: `reboot-loop.ps1`, `README.md`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of crash-log output flow.

### 2026-03-18 - Avoid helper names that collide with built-in ScheduledTasks cmdlets

- Date: 2026-03-18
- Problem: `Show current status` could fail after stopping the test with a parameter-binding error against `Get-ScheduledTaskInfo`.
- Root cause: A local helper function reused the name of the built-in `Get-ScheduledTaskInfo` cmdlet, and the collision produced the wrong parameter contract at runtime.
- Guardrail/rule: Do not name local helpers the same as ScheduledTasks cmdlets. Use repo-specific helper names such as `Get-RebootScheduledTask`.
- Files affected: `reboot-loop.ps1`, `CHANGELOG.md`
- Validation/tests run: PowerShell parser validation and manual review of the status lookup flow.
