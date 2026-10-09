#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$zip = Join-Path $OutputDirectory 'Star-Citizen-Easy-Cleaner-v2.0.0.zip'
$expected = @('SC Cleaner.bat','SC Cleaner.ps1','README.md','RELEASE_NOTES.md','VALIDATION.md')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $actual = @($archive.Entries | ForEach-Object { $_.FullName })
    if ($actual.Count -ne $expected.Count -or @((Compare-Object ($expected | Sort-Object) ($actual | Sort-Object))).Count -ne 0) {
        throw 'Release ZIP has missing, duplicate or unexpected paths.'
    }
    foreach ($entry in $archive.Entries) {
        $source = [IO.File]::ReadAllText((Join-Path $root $entry.FullName))
        if ($entry.FullName -match '\.(bat|ps1)$') { $source = $source -replace '\r?\n', "`r`n" }
        $bytes = [Text.Encoding]::UTF8.GetBytes($source)
        $stream = $entry.Open()
        $buffer = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($buffer)
            if ([Convert]::ToBase64String($buffer.ToArray()) -cne [Convert]::ToBase64String($bytes)) {
                throw "Release file differs from tested source: $($entry.FullName)"
            }
        } finally { $stream.Dispose(); $buffer.Dispose() }
    }
} finally { $archive.Dispose() }
$actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$record = [IO.File]::ReadAllText(($zip + '.sha256')).Trim()
if ($record -cne "$actualHash  $([IO.Path]::GetFileName($zip))") { throw 'Release checksum does not match.' }
Write-Host 'PASS release ZIP: exact paths, tested source bytes, CRLF scripts and SHA-256.'
