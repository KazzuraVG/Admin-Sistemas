. "$PSScriptRoot\lib\ssh_funcion.ps1"
. "$PSScriptRoot\lib\dhcp_funcion.ps1"
. "$PSScriptRoot\lib\dns_funcion.ps1"
. "$PSScriptRoot\lib\ftp_funcion.ps1"

function MostrarMenu {
    Write-Host ""
    Write-Host "***********************************************************" -ForegroundColor Cyan
    Write-Host "            PANEL DE CONTROL           " -ForegroundColor Green
    Write-Host "***********************************************************" -ForegroundColor Cyan
    Write-Host "[1] Administrar servicio SSH"  -ForegroundColor Yellow
    Write-Host "[2] Administrar servicio DHCP" -ForegroundColor Yellow
    Write-Host "[3] Administrar servicio DNS"  -ForegroundColor Yellow
    Write-Host "[4] Administrar servicio FTP"  -ForegroundColor Yellow
    Write-Host "[5] Terminar programa"         -ForegroundColor Yellow
    Write-Host ""
}

do {
    MostrarMenu
    $op = Read-Host "Selecciona una opcion"

    switch ($op) {
        "1" { menuSsh }
        "2" { menuDhcp }
        "3" { menuDns }
        "4" { menuFtp }
        "5" { Write-Host "Programa finalizado..." -ForegroundColor Cyan }
        default { Write-Host "Seleccion incorrecta." -ForegroundColor Red }
    }

    if ($op -ne "5") {
        $seguir = Read-Host "Deseas regresar al menu? (si/no)"
    }

} while ($op -ne "5" -and $seguir -eq "si")