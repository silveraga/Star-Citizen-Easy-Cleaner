# v2.0.0 - verified, conservative cache cleanup

Replaces v1's recursive removal of every non-GraphicsSettings subfolder with an exact allowlist of documented Star Citizen shader/PSO artifacts. Default double-click is read-only simulation; cleanup requires review and typing CLEAN.

Adds known-folder root resolution, constrained 4.x build recognition, preflight and fresh-inventory checks, refusal of links/junctions and unexpected settings, game/launcher process checks, literal file deletion, empty-directory-only removal, and actionable errors/exit codes.

Unknown files remain intact, including beside a recognized cache marker. This is not a complete DX11 or GPU-driver cache reset. Actual in-game behavior and coverage of every 4.x patch are not certified. This release is a prerelease pending in-game validation.

Extract the ZIP and keep SC Cleaner.bat and SC Cleaner.ps1 together. The bundled README lists sources, exact cleanup scope, and usage. A SHA-256 checksum accompanies the ZIP.
