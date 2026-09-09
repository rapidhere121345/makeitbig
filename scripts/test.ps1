$ErrorActionPreference = "Stop"
$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }
& $GodotBin --headless --path . --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --script res://tests/run_all.gd
if ($LASTEXITCODE -ne 0) { throw "Godot tests failed with exit code $LASTEXITCODE" }

$StateDir = Join-Path (Get-Location) "build/test-state"
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
$ExpectedHash = $null
foreach ($RenderRate in 30, 60, 144) {
    $HashPath = Join-Path $StateDir "${RenderRate}hz.sha256"
    & $GodotBin --headless --fixed-fps $RenderRate --path . -- --auto-smoke "--state-hash-out=$HashPath"
    if ($LASTEXITCODE -ne 0) { throw "${RenderRate}Hz replay failed with exit code $LASTEXITCODE" }
    $ActualHash = (Get-Content $HashPath -Raw).Trim()
    if ($null -eq $ExpectedHash) {
        $ExpectedHash = $ActualHash
    } elseif ($ActualHash -ne $ExpectedHash) {
        throw "Render-rate replay mismatch: 30Hz=$ExpectedHash ${RenderRate}Hz=$ActualHash"
    }
}
Write-Output "PASS  30/60/144Hz full automation replay: $ExpectedHash"
