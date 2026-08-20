$ErrorActionPreference = 'Stop'

$testFiles = @(
    Get-ChildItem -LiteralPath 'integration_test' -Filter '*_test.dart' -File |
        Sort-Object -Property Name
)

if ($testFiles.Count -eq 0) {
    throw 'No integration test files found.'
}

$failed = $false
foreach ($testFile in $testFiles) {
    Write-Output "::group::$($testFile.Name)"
    flutter test $testFile.FullName -d windows
    if ($LASTEXITCODE -ne 0) {
        $failed = $true
    }
    Write-Output '::endgroup::'
}

if ($failed) {
    exit 1
}
