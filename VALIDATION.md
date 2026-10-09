# Validation record - v2.0.0

Base repository commit: `ce321a970672433e04e04c98ee3d69de2ef105eb` (`main`). Verification date: 2026-10-09 UTC.

| Check | Result |
| --- | --- |
| Actual PowerShell implementation, isolated fixtures, PowerShell 7.4.13 on Linux | **26 test cases passed** |
| Default read-only user flow and cancellation | Passed; file hashes unchanged |
| Cleanup allowlist and preservation of settings/other data | Passed; only exact documented artifacts removed |
| Root validation, stale/injected plan, process checks/failures | Passed |
| Symlink/junction-style reparse paths and literal special characters | Passed on Linux symlinks; Windows junction branch not executed here |
| Process/content arriving during cleanup or confirmation | Passed; stop without recursive deletion |
| Windows PowerShell 5.1 and PowerShell 7 on Windows | **Not executed**; included workflow runs 29 cases on each |
| Windows file locking, read-only attributes, real process lookup, Batch smoke tests | **Not executed**; Windows-specific tests included |
| In-game test on a real Star Citizen 4.x installation | **Not executed** |
| ZIP paths, exact script bytes/CRLF, CRC and SHA-256 | Verified during packaging |
| Integration patch applies cleanly to the base commit | Verified with `git apply --check` and an isolated checkout |

The harness creates unique temporary synthetic fixtures. Its cleanup exercises only those synthetic cache artifacts. It does not open or modify the user's game installation or PC. The Windows Batch smoke test is read-only and previews only the CI runner's known folder.

The implementation intentionally preserves unidentified DX11/cache formats. It is not a complete shader-cache reset and is delivered as a prerelease candidate. Test success validates the implemented boundaries, not support for all layouts or proof of previous data loss.

## Initial delivery attempt

GitHub metadata reports push permission for the account, but the connected integration rejected both Git-tree creation and branch creation with HTTP 403, `Resource not accessible by integration`. Command-line push also had no authenticated credential. No remote changes or Release were published during that initial attempt. The supplied patch and downloadable ZIP were the fallback requested by the owner. A subsequent integration attempt is validating the same implementation on a separate branch before updating main.
