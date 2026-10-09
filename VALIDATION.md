# Validation record - v2.0.0

Base repository commit: `ce321a970672433e04e04c98ee3d69de2ef105eb` (`main`). Verification date: 2026-10-09 UTC.

Runtime/test implementation verified at commit `1ce88fddb5900610e949258771cfa578b2100954`. [Windows CI evidence](https://github.com/silveraga/Star-Citizen-Easy-Cleaner/actions/runs/37884473106) includes both PowerShell versions and release packaging. Later documentation-only commits are checked again before integration.

| Check | Result |
| --- | --- |
| Actual PowerShell implementation, isolated fixtures, PowerShell 7.4.13 on Linux | **26 test cases passed** |
| Default read-only user flow and cancellation | Passed; file hashes unchanged |
| Cleanup allowlist and preservation of settings/other data | Passed; only exact documented artifacts removed |
| Root validation, stale/injected plan, process checks/failures | Passed |
| Symlink/junction-style reparse paths and literal special characters | Passed on Linux symlinks and Windows junctions |
| Process/content arriving during cleanup or confirmation | Passed; stop without recursive deletion |
| Windows PowerShell 5.1 and PowerShell 7 on Windows | **29 test cases passed on each**, in isolated GitHub Actions runners |
| Windows file locking, read-only attributes, real process lookup, Batch smoke tests | Passed on both Windows jobs |
| In-game test on a real Star Citizen 4.x installation | **Not executed** |
| ZIP paths, exact script bytes/CRLF and SHA-256 | Passed on both Windows jobs; ZIP contains exactly the five intended files |
| Integration patch applies cleanly to the base commit | Verified with `git apply --check` and an isolated checkout |

The harness creates unique temporary synthetic fixtures. Its cleanup exercises only those synthetic cache artifacts. It does not open or modify the user's game installation or PC. The Windows Batch smoke test is read-only and previews only the CI runner's known folder.

The implementation intentionally preserves unidentified DX11/cache formats. It is not a complete shader-cache reset and is delivered as a prerelease candidate. Test success validates the implemented boundaries, not support for all layouts or proof of previous data loss.
