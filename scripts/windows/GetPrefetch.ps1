$computerListFile = "ComputerList.txt"

if (-not (Test-Path -Path $computerListFile)) {
    Write-Error "Computer list file not found: $computerListFile"
    exit
}

$computers = Get-Content -Path $computerListFile |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

foreach ($computer in $computers) {
    try {
        # Verify that WinRM is available
        Test-WSMan -ComputerName $computer -ErrorAction Stop | Out-Null

        Write-Host "========== $computer ==========" -ForegroundColor Cyan

        Invoke-Command -ComputerName $computer -ScriptBlock {
            $prefetchPath = 'C:\Windows\Prefetch'

            Get-ChildItem -Path $prefetchPath -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -eq '.pf' } |
                ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName = $env:COMPUTERNAME
                        PrefetchFile = $_.Name
                        Executable   = ($_.Name -split '-')[0]
                        LastRunTime  = $_.LastWriteTime
                        FileSizeKB   = [math]::Round($_.Length / 1KB, 2)
                    }
                }
        } |
        Sort-Object LastRunTime -Descending |
        Format-Table -AutoSize
    }
    catch {
        Write-Warning "Could not query $computer : $($_.Exception.Message)"
    }
}
