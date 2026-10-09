# Star Citizen Easy Cleaner 2.0.0

A Windows Batch launcher with a PowerShell 5.1+ engine for **conservative, verified cache cleanup**. Double-clicking runs a simulation. It does not reset graphics preferences or keybindings.

## Download and use

Download the ZIP from [Releases](https://github.com/silveraga/Star-Citizen-Easy-Cleaner/releases), then **extract the entire ZIP**. Keep `SC Cleaner.bat` and `SC Cleaner.ps1` together. The old standalone v1.0 Batch release from May 2024 uses broad recursive deletion; use v2 instead.

1. Double-click `SC Cleaner.bat` to see the exact files and empty directories planned for removal. This is read-only.
2. Close Star Citizen and the RSI Launcher.
3. From Command Prompt in the extracted folder, run `"SC Cleaner.bat" --clean`.
4. Review the new plan and type `CLEAN` to confirm. Any other response cancels. Leave shader optimization time on the next launch.

```bat
"SC Cleaner.bat" --dry-run
"SC Cleaner.bat" --clean
"SC Cleaner.bat" --help
```

No administrator rights, installation, registry edits, or system-wide execution-policy changes are required. The Batch wrapper uses `-ExecutionPolicy Bypass` for that PowerShell process only; organizational policy may still block execution. The window remains open so errors can be read. Advanced users can run `powershell.exe -NoProfile -File ".\SC Cleaner.ps1" -Mode Preview` or `-Mode Clean` directly.

## Exact scope for Star Citizen 4.x

The root is the current user's **Windows LocalApplicationData known folder** plus `Star Citizen`, normally `%LOCALAPPDATA%\Star Citizen`. A modified environment variable cannot redirect the cleaner. Only immediate version folders matching `starcitizen_(sc-alpha-4.<minor>.<patch>[suffix])_<alphanumeric-id>_<number>` are considered. Every matching version, including retained older 4.x builds and matching test builds, is considered; there is no claim that the newest folder is the active build.

| Relative path beneath a recognized version folder | Action |
| --- | --- |
| `Shaders\PSOCacheBuild.info` | Delete the documented shader precompilation marker |
| `Shaders\VulkanShaderCache\PipelineCache.sca` | Delete the documented game-managed Vulkan pipeline cache |
| `VulkanShaderCache\PipelineCache.sca` | Delete that exact artifact if present in the sibling layout |
| Corresponding `Shaders` / `VulkanShaderCache` directories | Remove **only if empty**, with no unidentified child directory |
| Everything else | Preserve |

**A recognized marker never authorizes deleting other files beside it.** Unknown files in even a recognized cache directory remain in place and are reported. The exact filenames and paths are compared case-insensitively, as on Windows.

This is intentionally narrower than v1. It **does not promise complete DX11 shader-cache cleanup**, complete driver-cache cleanup, or compatibility with all present/future layouts. A DX11-only cache without the documented artifacts is preserved. No undocumented extensions, sibling folders, or future major versions are guessed. The sibling Vulkan location is accepted only when the same exact `PipelineCache.sca` artifact exists; it is not claimed as universal across 4.x.

The following remain untouched: version folders themselves, `GraphicsSettings`, `USER`, control mappings, character presets, screenshots, `user.cfg`, crash logs and `payload.zip`, unknown siblings, game-install directories, launcher data, NVIDIA/AMD caches and other games. If a known configuration/log extension or protected user-data directory appears **inside a candidate cache**, the whole preflight fails before any deletion.

## Safety and errors

- Simulation is the default. Real deletion requires `--clean` and typing `CLEAN`.
- Invalid roots, files masquerading as cache directories, junctions, symlinks and all reparse points on targeted paths or their ancestors are refused. Links are checked before descending.
- All candidates are inspected before the first deletion. A failed inspection aborts the operation.
- The file inventory is regenerated after confirmation; a changed plan is refused. File type, size, timestamp and path links are rechecked before deletion.
- The game/launcher must be closed before and during cleanup. A process-enumeration error also stops cleanup.
- Every file is removed individually by literal path. **There is no recursive directory deletion, wildcard deletion, forced unlock, or read-only override.** Directories are removed only using nonrecursive empty-directory deletion.
- A locked/read-only file, access error, newly added content or newly running process stops cleanup and reports the number of files already deleted. Cleanup is not transactional: earlier cache deletions are not rolled back.

These checks reduce accidental deletion and ordinary changes during cleanup. They are not a filesystem transaction or a security boundary against a malicious process racing individual path checks. Do not restart the game/launcher while cleaning.

| Exit code | Meaning |
| --- | --- |
| `0` | Simulation, cancellation, no-op, or cleanup completed without unidentified items |
| `1` | Safety check or I/O error; read the message, including any partial-deletion count |
| `2` | Invalid Batch arguments |
| `3` | Simulation/cleanup finished with unidentified items deliberately preserved; not a full cache reset |

## Evidence and limits

Research checked on **2026-10-09 (UTC)**:

- [CIG Alpha 3.23 patch notes](https://robertsspaceindustries.com/en/comm-link/Patch-Notes/19915-Star-Citizen-Alpha-3230) establish the `%localappdata%\Star Citizen` cache location and distinguish graphics settings from Vulkan shader/pipeline caches. These historical notes alone do **not** prove every 4.x layout.
- [Silvan-CIG's first-person explanation, 24 July 2026](https://www.reddit.com/r/starcitizen/comments/1v4y2ga/thought_this_fit_here/) documents `Shaders/PSOCacheBuild.info` and `Shaders/VulkanShaderCache/PipelineCache.sca`, their purpose, and recompilation behavior. His [CIG-hosted profile](https://robertsspaceindustries.com/community-hub/user/Silvan-CIG) identifies him as an engine/graphics programmer. His comment spells the root `starcitizen` without a space; the cleaner targets only CIG Support's officially documented `Star Citizen` root with a space. The no-space variant is not inferred to be equivalent or targeted.
- [CIG: files for RSI Support](https://support.robertsspaceindustries.com/hc/en-us/articles/360000065688-Send-In-Game-Files-for-RSI-Support), updated June 2026, documents crash reports and `payload.zip` under the same local root. It must not be treated as an exclusively disposable cache container.
- [CIG: export/import custom profiles](https://support.robertsspaceindustries.com/hc/en-us/articles/360000183328-Create-export-and-import-custom-profiles) documents mappings under the install's `USER` tree, outside this tool's scope.

No game install or actual user cache has been inspected or modified to assert runtime coverage. Compatibility means recognizing these documented artifacts in the constrained 4.x folder layout, not certification of every 4.x patch. We do not claim that v1 has already caused data loss.

## Tests and release process

Run `powershell.exe -NoProfile -File tests\Test-Cleaner.ps1` (or `pwsh -NoProfile -File tests/Test-Cleaner.ps1`). The test harness creates its own unique temporary fixture directory. It tests actual planning/deletion code against synthetic data; it never cleans the real user's game root. Only the Windows Batch smoke test reads the runner's real known folder in simulation mode. The fixtures are left for inspection.

Tests cover byte-for-byte preservation, exact allowlisting, unverified content, malformed roots/versions, stale or injected plans, literal special characters, process detection/failures, junctions/symlinks, and Windows locked/read-only files. CI runs Windows PowerShell 5.1 and PowerShell 7. After both pass on `main`, CI packages the two scripts and documentation, writes a SHA-256 checksum, and prepares a downloadable **prerelease** for v2.0.0. A prerelease reflects that no in-game validation has been performed.

The release is built from the tested commit, not an unrelated old Batch asset. `scripts/Build-Release.ps1` also builds the ZIP locally. Do not download only the Batch file: its companion PowerShell script is required.
