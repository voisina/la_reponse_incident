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
            Get-NetTCPConnection |
                Where-Object {
                    $_.State -eq 'Established' -and
                    $_.RemoteAddress -ne '127.0.0.1' -and
                    $_.RemoteAddress -ne '::1'
                } |
                ForEach-Object {
                    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue

                    [PSCustomObject]@{
                        LocalAddress  = $_.LocalAddress
                        LocalPort     = $_.LocalPort
                        RemoteAddress = $_.RemoteAddress
                        RemotePort    = $_.RemotePort
                        State         = $_.State
                        ProcessName   = $proc.ProcessName
                        PID           = $_.OwningProcess
                    }
                }
        } |
        Sort-Object ProcessName |
        Format-Table -AutoSize
    }
    catch {
        Write-Warning "Failed to query $computer : $($_.Exception.Message)"
    }
}
