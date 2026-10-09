#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Preview', 'Clean', 'Help')][string]$Mode = 'Preview')

# Dot sourcing exposes the same implementation to isolated fixture tests only.
# The production entry point has no arbitrary-path or unattended-delete option.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SCPlainPath {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing link/junction/reparse point: $current"
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
}

function Get-SCRoot {
    $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($local) -or -not [IO.Path]::IsPathRooted($local)) {
        throw 'Windows LocalApplicationData is unavailable. No files were changed.'
    }
    # Use the Windows known folder, not a caller-supplied environment variable.
    return [IO.Path]::Combine($local, 'Star Citizen')
}

function Get-SCProcesses {
    # Enumerating all processes avoids treating a failed name lookup as "not running".
    return @(Get-Process -ErrorAction Stop | Where-Object {
        $_.ProcessName -in @('StarCitizen', 'RSI Launcher', 'RSILauncher')
    })
}

function Assert-SCClosed {
    $active = @(Get-SCProcesses)
    if ($active.Count -gt 0) {
        throw ('Close Star Citizen and the RSI Launcher first. Running: ' +
            (($active | ForEach-Object { $_.ProcessName }) -join ', '))
    }
}

function Get-SCCachePlan {
    param([Parameter(Mandatory)][string]$Root)
    if (-not [IO.Path]::IsPathRooted($Root)) { throw 'Refusing a relative root path.' }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([IO.Path]::GetFileName($rootPath) -ine 'Star Citizen') {
        throw 'Refusing root: the final folder must be exactly Star Citizen.'
    }
    $files = New-Object 'System.Collections.Generic.List[object]'
    $dirs = New-Object 'System.Collections.Generic.List[string]'
    $caches = New-Object 'System.Collections.Generic.List[string]'
    $skipped = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-Path -LiteralPath $rootPath)) {
        $ancestor = [IO.Directory]::GetParent($rootPath)
        while ($ancestor -and -not (Test-Path -LiteralPath $ancestor.FullName)) {
            $ancestor = $ancestor.Parent
        }
        if ($ancestor) { Assert-SCPlainPath $ancestor.FullName }
        return [pscustomobject]@{Root=$rootPath; Files=@(); Directories=@(); Caches=@(); Skipped=@()}
    }
    Assert-SCPlainPath $rootPath
    if (-not (Get-Item -LiteralPath $rootPath -Force).PSIsContainer) { throw 'Root is not a directory.' }
    # Only known 4.x build folder syntax. Old/future/unknown layouts stay untouched.
    $versionPattern = '^starcitizen_\(sc-alpha-4\.\d+\.\d+(?:[a-z0-9.-]*)\)_[a-z0-9]+_\d+$'
    foreach ($version in @(Get-ChildItem -LiteralPath $rootPath -Force -Directory)) {
        if ($version.Name -notmatch $versionPattern) { continue }
        Assert-SCPlainPath $version.FullName
        foreach ($name in @('Shaders', 'VulkanShaderCache')) {
            $cache = Join-Path $version.FullName $name
            if (-not (Test-Path -LiteralPath $cache)) { continue }
            Assert-SCPlainPath $cache
            if (-not (Get-Item -LiteralPath $cache -Force).PSIsContainer) {
                throw "Expected a cache directory, found a file: $cache"
            }
            # Walk one level at a time and refuse links BEFORE descending.
            $cacheFiles = New-Object 'System.Collections.Generic.List[object]'
            $cacheDirs = New-Object 'System.Collections.Generic.List[string]'
            $pending = New-Object 'System.Collections.Generic.Stack[string]'
            $pending.Push($cache)
            while ($pending.Count -gt 0) {
                $dir = $pending.Pop()
                Assert-SCPlainPath $dir
                $cacheDirs.Add($dir)
                foreach ($item in @(Get-ChildItem -LiteralPath $dir -Force)) {
                    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                        throw "Refusing link/junction/reparse point: $($item.FullName)"
                    }
                    if ($item.PSIsContainer) {
                        if ($item.Name -in @('GraphicsSettings','USER','Controls','Mappings','CustomCharacters','ScreenShots')) {
                            throw "Unexpected user-data folder inside cache; nothing will be deleted: $($item.FullName)"
                        }
                        $pending.Push($item.FullName)
                    } else {
                        if ($item.Extension -in @('.json','.xml','.cfg','.ini','.log','.dmp','.zip') -or $item.Name -ieq 'DXDiag.txt') {
                            throw "Unexpected settings/log/user file inside cache; nothing will be deleted: $($item.FullName)"
                        }
                        $cacheFiles.Add([pscustomobject]@{
                            Path=$item.FullName; Length=$item.Length; Ticks=$item.LastWriteTimeUtc.Ticks
                        })
                    }
                }
            }
            # Cache identity needs a documented artifact, not just a folder name.
            $markers = if ($name -eq 'Shaders') {
                @((Join-Path $cache 'PSOCacheBuild.info'),
                  ([IO.Path]::Combine($cache, 'VulkanShaderCache', 'PipelineCache.sca')))
            } else { @((Join-Path $cache 'PipelineCache.sca')) }
            $verified = @($cacheFiles | Where-Object { $_.Path -in $markers }).Count -gt 0
            if (-not $verified) {
                $skipped.Add("Unverified cache (no documented marker); preserved: $cache")
                continue
            }
            $caches.Add($cache)
            # A marker does NOT authorize deleting everything beside it.
            # Only the exact documented artifacts are eligible; unknown content stays.
            foreach ($file in $cacheFiles) {
                if ($file.Path -in $markers) { $files.Add($file) }
                else { $skipped.Add("Unidentified cache content; preserved: $($file.Path)") }
            }
            $allowedDirs = @($cache)
            if ($name -eq 'Shaders') { $allowedDirs += (Join-Path $cache 'VulkanShaderCache') }
            foreach ($dir in $cacheDirs) {
                if ($dir -notin $allowedDirs) {
                    $skipped.Add("Unidentified cache directory; preserved: $dir")
                    continue
                }
                $prefix = $dir + [IO.Path]::DirectorySeparatorChar
                $otherFiles = @($cacheFiles | Where-Object {
                    $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and $_.Path -notin $markers
                })
                $otherDirs = @($cacheDirs | Where-Object {
                    $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and $_ -notin $allowedDirs
                })
                if ($otherFiles.Count -eq 0 -and $otherDirs.Count -eq 0) { $dirs.Add($dir) }
            }
        }
    }
    return [pscustomobject]@{
        Root=$rootPath; Files=@($files.ToArray() | Sort-Object Path)
        Directories=@($dirs.ToArray() | Sort-Object @{Expression={$_.Length};Descending=$true}, @{Expression={$_}})
        Caches=@($caches.ToArray()); Skipped=@($skipped.ToArray())
    }
}

function Show-SCPlan {
    param([Parameter(Mandatory)]$Plan)
    Write-Host "Root: $($Plan.Root)"
    foreach ($message in $Plan.Skipped) { Write-Warning $message }
    foreach ($file in $Plan.Files) { Write-Host "[DELETE FILE] $($file.Path) ($($file.Length) bytes)" }
    foreach ($dir in $Plan.Directories) { Write-Host "[REMOVE IF EMPTY] $dir" }
    $bytes = 0L
    foreach ($file in $Plan.Files) { $bytes += $file.Length }
    Write-Host ("Plan: {0} files, {1} directories, {2:N0} bytes. {3} unidentified items preserved." -f
        $Plan.Files.Count, $Plan.Directories.Count, $bytes, $Plan.Skipped.Count)
}

function Invoke-SCCachePlan {
    param([Parameter(Mandatory)]$Plan, [switch]$DryRun)
    if ($DryRun) { Show-SCPlan $Plan; return }
    Assert-SCClosed
    # Rebuild the entire inventory before the first mutation. No caller-injected paths.
    $fresh = Get-SCCachePlan -Root $Plan.Root
    $before = $Plan | ConvertTo-Json -Depth 5 -Compress
    $after = $fresh | ConvertTo-Json -Depth 5 -Compress
    if ($before -cne $after) { throw 'Cache inventory changed after preview. Run the cleaner again.' }
    $removed = 0
    try {
        foreach ($file in $fresh.Files) {
            Assert-SCClosed
            Assert-SCPlainPath $file.Path
            $item = Get-Item -LiteralPath $file.Path -Force
            if ($item.PSIsContainer -or $item.Length -ne $file.Length -or $item.LastWriteTimeUtc.Ticks -ne $file.Ticks) {
                throw "File changed after preview: $($file.Path)"
            }
            # Literal .NET paths, no wildcards, no recursive deletion, no forced unlock.
            [IO.File]::Delete($file.Path)
            $removed++
            Write-Host "[DELETED] $($file.Path)"
        }
        foreach ($dir in $fresh.Directories) {
            Assert-SCClosed
            Assert-SCPlainPath $dir
            # Never recursively remove a directory: a new/unexpected file stops cleanup.
            [IO.Directory]::Delete($dir, $false)
            Write-Host "[REMOVED EMPTY] $dir"
        }
    } catch {
        throw "Cleanup stopped after deleting $removed file(s); remaining data preserved. $($_.Exception.Message)"
    }
}

function Invoke-SCCleaner {
    param([ValidateSet('Preview', 'Clean', 'Help')][string]$Mode = 'Preview')
    if ($Mode -eq 'Help') {
        Write-Host 'SC Easy Cleaner 2.0.0: Preview (default), Clean (type CLEAN to confirm), Help.'
        return 0
    }
    Write-Host 'Star Citizen Easy Cleaner 2.0.0'
    $plan = Get-SCCachePlan -Root (Get-SCRoot)
    Show-SCPlan $plan
    if ($Mode -eq 'Preview') {
        Write-Host 'SIMULATION ONLY. No files were changed. Use --clean to review and confirm cleanup.'
    } elseif ($plan.Files.Count -eq 0) {
        Write-Host 'No verified cache files to remove.'
    } else {
        Assert-SCClosed
        $answer = Read-Host 'Permanently remove only the cache items shown above? Type CLEAN to proceed'
        if ($answer -cne 'CLEAN') { Write-Host 'Cancelled. No files were changed.'; return 0 }
        Invoke-SCCachePlan -Plan $plan
        Write-Host 'Verified cache cleanup completed. Let Star Citizen rebuild its shaders on next launch.'
    }
    if ($plan.Skipped.Count -gt 0) { return 3 }
    return 0
}

if ($MyInvocation.InvocationName -eq '.') { return }
try {
    if ($Mode -ne 'Help' -and [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'The cleaner entry point is Windows-only. No files were changed.'
    }
    exit (Invoke-SCCleaner -Mode $Mode)
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
}
