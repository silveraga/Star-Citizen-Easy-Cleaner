# Developing and releasing v2.0.0

Work on a branch in a checkout of `silveraga/Star-Citizen-Easy-Cleaner`. Run the actual implementation against isolated synthetic fixtures before merging changes.

On Windows, validate both supported shells, build the download, and compare every packaged file with its source:

```powershell
powershell.exe -NoProfile -File tests\Test-Cleaner.ps1
pwsh -NoProfile -File tests\Test-Cleaner.ps1
powershell.exe -NoProfile -File scripts\Build-Release.ps1
powershell.exe -NoProfile -File scripts\Test-Release.ps1
```

GitHub Actions tests Windows PowerShell 5.1 and PowerShell 7 on `fix/**` branches and pull requests. Both jobs also verify ZIP contents, CRLF script bytes and SHA-256. **After integration into main, the workflow runs these checks again and publishes v2.0.0 as a downloadable prerelease only if both jobs pass.** It includes a ZIP and SHA-256 file and targets the tested commit. If that version already exists, it leaves the existing Release assets intact. For a subsequent version, update the version in the scripts, workflow and documentation together.

If automated publication is not wanted, omit the `release` job before merging and upload the ZIP/checksum built by `scripts/Build-Release.ps1` manually. Do not reuse the old `auto` tag/2024 Batch asset as the v2 download. The v2 Batch file requires its companion PowerShell file.

Windows tests have passed for v2.0.0. In-game validation remains pending. See `VALIDATION.md` for the exact evidence and `README.md` for the deliberately narrow cache scope. These tests never delete anything in a user's real Star Citizen installation.
