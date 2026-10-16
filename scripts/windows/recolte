

$computerListFile = "ComputerList.txt"
$suspiciousFile = "SuspiciousProcesses.txt"

if (-Not (Test-Path $computerListFile)) {
    Write-Error "Computer list file not found: $computerListFile"
    exit
}

if (-Not (Test-Path $suspiciousFile)) {
    Write-Error "Suspicious processes file not found: $suspiciousFile"
    exit
}

$computers = Get-Content -Path $computerListFile |
    Where-Object { $_ -ne "" }

$suspiciousProcesses = Get-Content -Path $suspiciousFile |
    Where-Object { $_ -ne "" }

foreach ($computer in $computers) {
    try {
        # Test WinRM connectivity
        Test-WSMan -ComputerName $computer -ErrorAction Stop |
            Out-Null

        Write-Host "========== $computer ==========" -ForegroundColor Cyan

        # Query processes remotely
        $processes = Invoke-Command -ComputerName $computer -ScriptBlock {
            param($names)

            Get-Process |
                Where-Object { $names -contains $_.Name } |
                Select-Object Name, Id, CPU, WS
        } -ArgumentList $suspiciousProcesses -ErrorAction Stop

        if ($processes) {
            $processes |
                Format-Table Name, Id, CPU, WS -AutoSize
        }
        else {
            Write-Host "No suspicious processes found." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Could not query $computer : $_"
    }
}
