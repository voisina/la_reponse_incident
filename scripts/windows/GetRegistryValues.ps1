$computerListFile = "ComputerList.txt"

$computers = Get-Content $computerListFile | Where-Object { $_ -ne "" }

foreach ($computer in $computers) {
    try {
        Write-Host "========== $computer ==========" -ForegroundColor Cyan

        Invoke-Command -ComputerName $computer -ScriptBlock {
            $key = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'

            $key.GetValueNames() | ForEach-Object {
                [PSCustomObject]@{
                    ValueName = $_
                    ValueData = $key.GetValue($_)
                }
            }
        } | Format-Table -AutoSize
    }
    catch {
        Write-Warning "Could not query $computer : $_"
    }
}
