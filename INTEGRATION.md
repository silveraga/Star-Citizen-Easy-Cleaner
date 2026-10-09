# Integrating v2.0.0

The patch was prepared against `silveraga/Star-Citizen-Easy-Cleaner` main commit `ce321a970672433e04e04c98ee3d69de2ef105eb`. It changes the Batch launcher and README and adds the PowerShell engine, tests, packaging, validation notes, and a Windows CI/release workflow.

In a checkout of the repository, with a clean working tree:

```sh
git switch -c fix/safe-cache-cleaner-v2
git apply --check /path/to/Star-Citizen-Easy-Cleaner-v2.0.0.patch
git apply /path/to/Star-Citizen-Easy-Cleaner-v2.0.0.patch
```

On Windows, validate the tests and build the download:

```powershell
powershell.exe -NoProfile -File tests\Test-Cleaner.ps1
pwsh -NoProfile -File tests\Test-Cleaner.ps1
powershell.exe -NoProfile -File scripts\Build-Release.ps1
```

Then commit and push the branch through your normal GitHub access. GitHub Actions tests both Windows PowerShell 5.1 and PowerShell 7 on `fix/**` branches and pull requests. **After integration into main, the workflow runs the tests again and publishes v2.0.0 as a downloadable prerelease only if both pass.** It includes a ZIP and SHA-256 file and targets the tested commit. If that version already exists, it leaves the existing Release assets intact.

If automated publication is not wanted, omit the `release` job before merging and upload the ZIP/checksum built by `scripts/Build-Release.ps1` manually. Do not reuse the old `auto` tag/2024 Batch asset as the v2 download. The v2 Batch file requires its companion PowerShell file.

The separate runtime ZIP is immediately downloadable for inspection, but Windows and in-game tests were not possible in this session. See `VALIDATION.md` for the exact tested/pending checks and `README.md` for the deliberately narrow cache scope.
