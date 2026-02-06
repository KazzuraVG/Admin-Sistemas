Write-Host "Nombre del Equipo:"
Write-Host $env:COMPUTERNAME
Write-Host "Ip actual:"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "169.*"}
Write-Host "Espacio en disco: "
Get-PSDRIVE C
