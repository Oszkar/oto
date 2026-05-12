# Bootstrap a fresh checkout on a dev machine.
# Installs Cargo CLIs the workspace expects, then runs `flutter pub get`
# and `cargo check`.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$tools = @(
    @{ name = "flutter_rust_bridge_codegen"; args = @("--version", "^2") },
    @{ name = "cargo-ndk"; args = @() },
    @{ name = "cargo-nextest"; args = @() },
    @{ name = "cargo-deny"; args = @() }
)

foreach ($tool in $tools) {
    if (Get-Command $tool.name -ErrorAction SilentlyContinue) {
        Write-Host "[skip] $($tool.name) already installed"
        continue
    }
    Write-Host "[install] $($tool.name)"
    cargo install $tool.name @($tool.args) --locked
}

Push-Location "$root\app"
flutter pub get
Pop-Location

Push-Location "$root\native"
cargo check --workspace
Pop-Location
