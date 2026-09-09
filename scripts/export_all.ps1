$ErrorActionPreference = "Stop"
$GodotBin = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }
New-Item -ItemType Directory -Force -Path "build/linux", "build/windows" | Out-Null
& $GodotBin --headless --path . --export-release "Linux x86_64"
if ($LASTEXITCODE -ne 0) { throw "Linux export failed with exit code $LASTEXITCODE" }
& $GodotBin --headless --path . --export-release "Windows x86_64"
if ($LASTEXITCODE -ne 0) { throw "Windows export failed with exit code $LASTEXITCODE" }
