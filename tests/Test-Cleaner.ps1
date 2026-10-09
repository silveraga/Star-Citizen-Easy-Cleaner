#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'SC Cleaner.ps1')
$script:Passed = 0
$script:Workspace = Join-Path ([IO.Path]::GetTempPath()) ('sc-cleaner-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:Workspace) | Out-Null
$script:Version = 'starcitizen_(sc-alpha-4.9.0)_cc9wt_0'
$script:RealProcessLookup = ${function:Get-SCProcesses}
function Get-SCProcesses { return @() }
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    if ($null -eq $caught -or $caught -notmatch $Pattern) { throw "Expected error /$Pattern/, got: $caught" }
}
function New-Fixture {
    $root = Join-Path (Join-Path $script:Workspace ([Guid]::NewGuid().ToString('N'))) 'Star Citizen'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    return $root
}
function Put-File([string]$Root, [string]$Relative, [string]$Content = 'fixture') {
    $path = Join-Path $Root $Relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
    [IO.File]::WriteAllText($path, $Content)
    return $path
}
function Add-Cache([string]$Root) {
    Put-File $Root "$script:Version/Shaders/PSOCacheBuild.info" | Out-Null
    Put-File $Root "$script:Version/Shaders/VulkanShaderCache/PipelineCache.sca" | Out-Null
}
function Snapshot([string]$Root) {
    return (@(Get-ChildItem -LiteralPath $Root -Force -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}
function Test-Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:Passed++
    Write-Host "PASS $Name"
}

Test-Case 'empty/missing root is a safe no-op' {
    $root = Join-Path $script:Workspace 'missing/Star Citizen'
    $plan = Get-SCCachePlan $root
    Assert-True ($plan.Files.Count -eq 0) 'Expected no files'
    Invoke-SCCachePlan $plan -DryRun
    Invoke-SCCachePlan $plan
    Assert-True (-not (Test-Path -LiteralPath $root)) 'No root should be created'
}
Test-Case 'reject relative, empty, broad, and wrong-name roots' {
    Assert-Throws { Get-SCCachePlan 'Star Citizen' } 'relative'
    Assert-Throws { Get-SCCachePlan '' } 'empty'
    Assert-Throws { Get-SCCachePlan $script:Workspace } 'exactly Star Citizen'
    Assert-Throws { Get-SCCachePlan ([IO.Path]::GetPathRoot($script:Workspace)) } 'exactly Star Citizen'
}
Test-Case 'simulation preserves every byte and lists only verified caches' {
    $root = New-Fixture; Add-Cache $root
    Put-File $root "$script:Version/GraphicsSettings/GraphicsSettings.json" '{"renderer":1}' | Out-Null
    Put-File $root "$script:Version/USER/Controls/Mappings/layout.xml" | Out-Null
    Put-File $root 'payload.zip' | Out-Null
    $before = Snapshot $root
    $plan = Get-SCCachePlan $root
    Assert-True ($plan.Files.Count -eq 2) 'Expected two synthetic cache files'
    Invoke-SCCachePlan $plan -DryRun
    Assert-True ((Snapshot $root) -ceq $before) 'Dry run changed data'
}
Test-Case 'cleanup preserves settings, logs, characters, screenshots, unknown data and versions' {
    $root = New-Fixture; Add-Cache $root
    $keep = @('payload.zip','gpu_error.log', "$script:Version/GraphicsSettings/GraphicsSettings.json",
        "$script:Version/USER/Controls/Mappings/layout.xml", "$script:Version/CustomCharacters/char.bin",
        "$script:Version/ScreenShots/shot.png", "$script:Version/OtherData/important.bin",
        "$script:Version/user.cfg", "$script:Version/Shaders/compiled/test[1]!&%.bin", 'unrelated/Shaders/PSOCacheBuild.info',
        'starcitizen_(sc-alpha-3.23.0)_abc_0/Shaders/PSOCacheBuild.info',
        'starcitizen_(sc-alpha-5.0.0)_abc_0/Shaders/PSOCacheBuild.info')
    $paths = @($keep | ForEach-Object { Put-File $root $_ 'KEEP EXACT BYTES' })
    $hashes = @($paths | ForEach-Object { (Get-FileHash -LiteralPath $_).Hash })
    Invoke-SCCachePlan (Get-SCCachePlan $root)
    for ($i=0; $i -lt $paths.Count; $i++) {
        Assert-True ((Get-FileHash -LiteralPath $paths[$i]).Hash -ceq $hashes[$i]) "Changed protected file $($paths[$i])"
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $root $script:Version)) 'Version folder deleted'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root "$script:Version/Shaders/PSOCacheBuild.info"))) 'Known cache file remains'
}
Test-Case 'sibling Vulkan cache requires and accepts PipelineCache.sca' {
    $root = New-Fixture
    Put-File $root "$script:Version/VulkanShaderCache/PipelineCache.sca" | Out-Null
    $plan = Get-SCCachePlan $root
    Assert-True ($plan.Files.Count -eq 1) 'Sibling Vulkan cache not recognized'
    Invoke-SCCachePlan $plan
    Assert-True ((Get-SCCachePlan $root).Files.Count -eq 0) 'Second run is not a no-op'
}
Test-Case 'nested pipeline marker alone identifies a cache' {
    $root = New-Fixture
    Put-File $root "$script:Version/Shaders/VulkanShaderCache/PipelineCache.sca" | Out-Null
    Assert-True ((Get-SCCachePlan $root).Files.Count -eq 1) 'Nested marker was ignored'
}
Test-Case 'unverified cache directories and unknown siblings are preserved' {
    $root = New-Fixture
    Put-File $root "$script:Version/Shaders/important.txt" | Out-Null
    Put-File $root "$script:Version/VulkanShaderCache/unknown.bin" | Out-Null
    Put-File $root "$script:Version/OtherCache/PSOCacheBuild.info" | Out-Null
    $before = Snapshot $root; $plan = Get-SCCachePlan $root
    Assert-True ($plan.Files.Count -eq 0 -and $plan.Skipped.Count -eq 2) 'Unknown cache accepted'
    Invoke-SCCachePlan $plan
    Assert-True ((Snapshot $root) -ceq $before) 'Unknown data deleted'
}
Test-Case 'lookalike versions and backup folders are never candidates' {
    $root = New-Fixture
    foreach ($v in @('starcitizen_(sc-alpha-4.9.0)_abc_0_backup','starcitizen_(sc-alpha-4.9.0)_abc_0x','4.9.0','other')) {
        Put-File $root "$v/Shaders/PSOCacheBuild.info" | Out-Null
    }
    Assert-True ((Get-SCCachePlan $root).Files.Count -eq 0) 'Lookalike accepted'
}
Test-Case 'unknown files beside known artifacts and their directories stay intact' {
    $root = New-Fixture; Add-Cache $root
    $unknown = Put-File $root "$script:Version/Shaders/VulkanShaderCache/my-notes.txt" 'KEEP'
    $other = Put-File $root "$script:Version/Shaders/custom/test[1]!&%.bin" 'KEEP'
    $plan = Get-SCCachePlan $root
    Assert-True ($plan.Files.Count -eq 2 -and $plan.Skipped.Count -eq 3) 'Allowlist expanded to neighbors'
    Assert-True ($plan.Directories.Count -eq 0) 'Nonempty unknown directories scheduled'
    Invoke-SCCachePlan $plan
    Assert-True ([IO.File]::ReadAllText($unknown) -eq 'KEEP') 'Unknown neighbor lost'
    Assert-True ([IO.File]::ReadAllText($other) -eq 'KEEP') 'Wildcard-like unknown neighbor lost'
}
Test-Case 'same cache filename at an unknown path does not qualify' {
    $root = New-Fixture; Add-Cache $root
    $unknown = Put-File $root "$script:Version/Shaders/Other/PipelineCache.sca" 'KEEP'
    $plan = Get-SCCachePlan $root
    Assert-True ($plan.Files.Count -eq 2) 'Filename-only match accepted'
    Invoke-SCCachePlan $plan
    Assert-True ([IO.File]::ReadAllText($unknown) -eq 'KEEP') 'Unknown path lost'
}
Test-Case 'LocalApplicationData environment tampering does not redirect the root' {
    $expected = Get-SCRoot
    $previous = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $script:Workspace 'malicious-root'
        Assert-True ((Get-SCRoot) -ceq $expected) 'Environment redirected root'
        $env:LOCALAPPDATA = ''
        Assert-True ((Get-SCRoot) -ceq $expected) 'Empty environment redirected root'
    } finally { $env:LOCALAPPDATA = $previous }
}
Test-Case 'a cache-name file is refused' {
    $root = New-Fixture; Put-File $root "$script:Version/Shaders" | Out-Null
    Assert-Throws { Get-SCCachePlan $root } 'found a file'
}
Test-Case 'configuration extensions inside a marked cache stop the entire operation' {
    foreach ($name in @('GraphicsSettings.json','settings.xml','user.cfg','config.ini','game.log','crash.dmp','payload.zip','DXDiag.txt')) {
        $root = New-Fixture; Add-Cache $root
        Put-File $root "$script:Version/Shaders/$name" | Out-Null
        $before = Snapshot $root
        Assert-Throws { Get-SCCachePlan $root } 'Unexpected settings/log/user file'
        Assert-True ((Snapshot $root) -ceq $before) 'Preflight mutated files'
    }
}
Test-Case 'protected directory inside cache stops preflight' {
    $root = New-Fixture; Add-Cache $root
    Put-File $root "$script:Version/Shaders/GraphicsSettings/renderer.bin" | Out-Null
    Assert-Throws { Get-SCCachePlan $root } 'Unexpected user-data folder'
}
Test-Case 'added, removed or modified files invalidate preview before any deletion' {
    foreach ($change in @('add','remove','modify')) {
        $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root
        if ($change -eq 'add') { Put-File $root "$script:Version/Shaders/new.bin" | Out-Null }
        if ($change -eq 'remove') { [IO.File]::Delete((Join-Path $root "$script:Version/Shaders/VulkanShaderCache/PipelineCache.sca")) }
        if ($change -eq 'modify') { Put-File $root "$script:Version/Shaders/PSOCacheBuild.info" 'changed bytes' | Out-Null }
        $before = Snapshot $root
        Assert-Throws { Invoke-SCCachePlan $plan } 'inventory changed'
        Assert-True ((Snapshot $root) -ceq $before) 'Stale plan deleted files'
    }
}
Test-Case 'injected outside-root file in a plan is rejected' {
    $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root
    $outside = Put-File $script:Workspace 'outside.txt' 'KEEP'
    $plan.Files += [pscustomobject]@{Path=$outside; Length=4; Ticks=0}
    Assert-Throws { Invoke-SCCachePlan $plan } 'inventory changed'
    Assert-True ([IO.File]::ReadAllText($outside) -eq 'KEEP') 'Outside file deleted'
}
Test-Case 'running game and launcher block mutations but allow preview' {
    $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root; $before = Snapshot $root
    foreach ($name in @('StarCitizen','RSI Launcher','RSILauncher')) {
        $script:FakeName = $name
        function Get-SCProcesses { return @([pscustomobject]@{ProcessName=$script:FakeName}) }
        Invoke-SCCachePlan $plan -DryRun
        Assert-Throws { Invoke-SCCachePlan $plan } 'Close Star Citizen'
    }
    function Get-SCProcesses { return @() }
    Assert-True ((Snapshot $root) -ceq $before) 'Running process guard failed'
}
Test-Case 'process enumeration failure stops cleanup' {
    $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root
    function Get-SCProcesses { throw 'simulated process enumeration denied' }
    Assert-Throws { Invoke-SCCachePlan $plan } 'enumeration denied'
    function Get-SCProcesses { return @() }
}
Test-Case 'process appearing after preflight stops before deletion' {
    $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root; $before = Snapshot $root
    $script:ProcessChecks = 0
    function Get-SCProcesses {
        $script:ProcessChecks++
        if ($script:ProcessChecks -gt 1) { return @([pscustomobject]@{ProcessName='StarCitizen'}) }
        return @()
    }
    Assert-Throws { Invoke-SCCachePlan $plan } 'Cleanup stopped after deleting 0'
    Assert-True ((Snapshot $root) -ceq $before) 'Files deleted after process appeared'
    function Get-SCProcesses { return @() }
}
Test-Case 'new content during deletion is never recursively removed' {
    $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root
    $script:ProcessChecks = 0
    $script:NewContentPath = Join-Path $root "$script:Version/Shaders/VulkanShaderCache/new-user-data.txt"
    function Get-SCProcesses {
        $script:ProcessChecks++
        if ($script:ProcessChecks -eq 4) { [IO.File]::WriteAllText($script:NewContentPath, 'KEEP') }
        return @()
    }
    Assert-Throws { Invoke-SCCachePlan $plan } 'Cleanup stopped after deleting 2'
    Assert-True ([IO.File]::ReadAllText($script:NewContentPath) -eq 'KEEP') 'New content deleted recursively'
    function Get-SCProcesses { return @() }
}
Test-Case 'literal special-character paths do not expand wildcards or shell syntax' {
    $base = Join-Path $script:Workspace ('space [x] &!% ' + [char]0xe9)
    $root = Join-Path $base 'Star Citizen'; Add-Cache $root
    Invoke-SCCachePlan (Get-SCCachePlan $root)
    Assert-True (Test-Path -LiteralPath (Join-Path $root $script:Version)) 'Literal version removed'
}
Test-Case 'default user flow is read-only and never asks for deletion' {
    $script:FlowRoot = New-Fixture; Add-Cache $script:FlowRoot
    $before = Snapshot $script:FlowRoot
    function Get-SCRoot { return $script:FlowRoot }
    function Read-Host { throw 'Preview must not ask for deletion' }
    Assert-True ((Invoke-SCCleaner) -eq 0) 'Default flow failed'
    Assert-True ((Snapshot $script:FlowRoot) -ceq $before) 'Default flow deleted files'
}
Test-Case 'clean user flow cancels on empty, lowercase, and other responses' {
    foreach ($response in @('', 'clean', 'yes', 'NO')) {
        $script:FlowRoot = New-Fixture; Add-Cache $script:FlowRoot
        $script:Response = $response; $before = Snapshot $script:FlowRoot
        function Get-SCRoot { return $script:FlowRoot }
        function Read-Host { return $script:Response }
        Assert-True ((Invoke-SCCleaner -Mode Clean) -eq 0) 'Cancellation code incorrect'
        Assert-True ((Snapshot $script:FlowRoot) -ceq $before) 'Cancelled flow deleted files'
    }
}
Test-Case 'CLEAN confirms only the exact artifacts and returns partial-scope code' {
    $script:FlowRoot = New-Fixture; Add-Cache $script:FlowRoot
    $unknown = Put-File $script:FlowRoot "$script:Version/Shaders/keep.txt" 'KEEP'
    function Get-SCRoot { return $script:FlowRoot }
    function Read-Host { return 'CLEAN' }
    Assert-True ((Invoke-SCCleaner -Mode Clean) -eq 3) 'Unidentified content not reported'
    Assert-True ([IO.File]::ReadAllText($unknown) -eq 'KEEP') 'User flow deleted unknown content'
    Assert-True ((Get-SCCachePlan $script:FlowRoot).Files.Count -eq 0) 'Known artifacts not cleaned'
}
Test-Case 'process starting while confirmation is open blocks deletion' {
    $script:FlowRoot = New-Fixture; Add-Cache $script:FlowRoot
    $before = Snapshot $script:FlowRoot; $script:AfterPrompt = $false
    function Get-SCRoot { return $script:FlowRoot }
    function Read-Host { $script:AfterPrompt = $true; return 'CLEAN' }
    function Get-SCProcesses {
        if ($script:AfterPrompt) { return @([pscustomobject]@{ProcessName='StarCitizen'}) }
        return @()
    }
    Assert-Throws { Invoke-SCCleaner -Mode Clean } 'Close Star Citizen'
    Assert-True ((Snapshot $script:FlowRoot) -ceq $before) 'Files deleted after confirmation race'
}
# Junctions work without symlink privileges on Windows. Linux uses directory symlinks.
Test-Case 'junction/symlink at root, ancestor, version, cache or descendant is refused' {
    foreach ($level in @('root','ancestor','version','cache','descendant')) {
        $root = New-Fixture; Add-Cache $root
        $outside = Join-Path $script:Workspace ('link-target-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($outside) | Out-Null
        Put-File $outside 'keep.bin' 'KEEP' | Out-Null
        $linkedRoot = $root
        $link = switch ($level) {
            'root' { Join-Path (Join-Path $script:Workspace ([Guid]::NewGuid().ToString('N'))) 'Star Citizen' }
            'ancestor' { Join-Path $script:Workspace ([Guid]::NewGuid().ToString('N')) }
            'version' { Join-Path $root 'starcitizen_(sc-alpha-4.8.0)_abc_0' }
            'cache' { Join-Path $root "$script:Version/VulkanShaderCache" }
            'descendant' { Join-Path $root "$script:Version/Shaders/link" }
        }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($link)) | Out-Null
        $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $kind -Path $link -Target $outside | Out-Null
        if ($level -eq 'root') { $linkedRoot = $link }
        if ($level -eq 'ancestor') { $linkedRoot = Join-Path $link 'Star Citizen' }
        Assert-Throws { Get-SCCachePlan $linkedRoot } 'link/junction/reparse'
        Assert-True ([IO.File]::ReadAllText((Join-Path $outside 'keep.bin')) -eq 'KEEP') 'Link target modified'
    }
}
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    Test-Case 'locked cache file produces an honest partial failure' {
        $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root
        $path = $plan.Files[0].Path
        $handle = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try { Assert-Throws { Invoke-SCCachePlan $plan } 'Cleanup stopped after deleting 0' }
        finally { $handle.Dispose() }
        Assert-True (Test-Path -LiteralPath $path) 'Locked file deleted'
    }
    Test-Case 'read-only cache file is not forcibly removed' {
        $root = New-Fixture; Add-Cache $root; $plan = Get-SCCachePlan $root
        [IO.File]::SetAttributes($plan.Files[0].Path, [IO.FileAttributes]::ReadOnly)
        Assert-Throws { Invoke-SCCachePlan $plan } 'Cleanup stopped after deleting 0'
    }
    Test-Case 'real game-process detection and batch argument handling' {
        # Run a renamed cmd.exe in our disposable workspace, never the game.
        $exe = Join-Path $script:Workspace 'StarCitizen.exe'
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32/cmd.exe') -Destination $exe
        $proc = Start-Process -FilePath $exe -ArgumentList '/c ping -n 30 127.0.0.1 >nul' -WindowStyle Hidden -PassThru
        try {
            Set-Item -Path function:Get-SCProcesses -Value $script:RealProcessLookup
            Assert-Throws { Assert-SCClosed } 'StarCitizen'
        } finally { Stop-Process -Id $proc.Id -ErrorAction SilentlyContinue; function Get-SCProcesses { return @() } }
        $batch = Join-Path (Split-Path $PSScriptRoot -Parent) 'SC Cleaner.bat'
        & $env:ComSpec /d /c ('""' + $batch + '" --help"')
        Assert-True ($LASTEXITCODE -eq 0) 'Batch help failed'
        & $env:ComSpec /d /c ('""' + $batch + '" --invalid"')
        Assert-True ($LASTEXITCODE -eq 2) 'Invalid arguments accepted'
        # Read-only batch preview against runner known folder; stdin prevents pause blocking.
        & $env:ComSpec /d /c ('""' + $batch + '" --dry-run <nul"')
        Assert-True ($LASTEXITCODE -eq 0) 'Batch preview failed'
    }
}
Write-Host "PASS TOTAL: $script:Passed cases. Fixtures only: $script:Workspace"
