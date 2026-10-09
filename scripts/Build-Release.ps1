#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
[IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$zip = Join-Path $OutputDirectory 'Star-Citizen-Easy-Cleaner-v2.0.0.zip'
$staging = Join-Path ([IO.Path]::GetTempPath()) ('sc-cleaner-package-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($staging) | Out-Null
$files = @('SC Cleaner.bat','SC Cleaner.ps1','README.md','RELEASE_NOTES.md','VALIDATION.md') | ForEach-Object {
    $source = Join-Path $root $_
    $target = Join-Path $staging $_
    $content = [IO.File]::ReadAllText($source)
    if ($_ -match '\.(bat|ps1)$') { $content = $content -replace '\r?\n', "`r`n" }
    [IO.File]::WriteAllText($target, $content, (New-Object Text.UTF8Encoding($false)))
    $target
}
Compress-Archive -LiteralPath $files -DestinationPath $zip -Force
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip + '.sha256'), "$hash  $([IO.Path]::GetFileName($zip))`n", (New-Object Text.UTF8Encoding($false)))
Write-Host "Built $zip"
Write-Host "SHA256 $hash"
