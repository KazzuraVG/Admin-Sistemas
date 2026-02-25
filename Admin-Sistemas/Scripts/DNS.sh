


You said:



function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            return $ip
        }
        Write-Host "Formato IPv4 inválido. Reintente." -ForegroundColor Red
    } while ($true)
}

function GestionarIpFija {
    Write-Host "n[Verificando Configuración de Red]" -ForegroundColor Cyan
    $interfaz = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1
    
    if ($interfaz.Dhcp -eq "Enabled") {
        Write-Host "ADVERTENCIA: El servidor tiene DHCP habilitado. Se requiere IP fija para DNS." -ForegroundColor Yellow
        $nuevaIp = validacionIp "Ingrese la IP estática para este servidor: "
        $mascara = Read-Host "Ingrese la máscara (ej. 24 para 255.255.255.0): "
        $gw = validacionIp "Ingrese el Gateway (Puerta de enlace): "
        
        Write-Host "Configurando IP estática..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $interfaz.InterfaceAlias -IPAddress $nuevaIp -PrefixLength $mascara -DefaultGateway $gw
        Write-Host "IP configurada con éxito." -ForegroundColor Green
    } else {
        $actual = (Get-NetIPAddress -InterfaceIndex $interfaz.InterfaceIndex -AddressFamily IPv4).IPAddress
        Write-Host "El servidor ya tiene una IP fija configurada: $actual" -ForegroundColor Green
    }
}

function ConfigurarDns {
    Write-Host "n=== CONFIGURACION DE ZONA Y REGISTROS ===" -ForegroundColor Blue
    
    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

    $ipDestino = validacionIp "Ingrese la IP a la que apuntara ${hostname}.${dominio} : "

    try {
        if (-not (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
            Write-Host "Zona $dominio creada." -ForegroundColor Green
        }
        
        Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino -AllowUpdateAny
        Write-Host "Registro configurado con exito." -ForegroundColor Green
    } catch {
        Write-Host "Error en la configuracion: $($_.Exception.Message)" -ForegroundColor Red
    }
} 

function borrarDominio{
    $borrar = read-host "ingrese el dominio que desea borrar (ej: reprobados.com)"
    if (get-DnsServerZone -name $borrar -erroraction silentlycontinue){
        try{
            remove-DnsServerZone -name $borrar -force
            write-host "el dominio $borrar a sido borrado correctamente" -foregroundcolor green
        } catch{
            write-host "error al eliminar el dominio: $($_.exception.message)" -foregroundcolor red
        }
    }else{
        write-host "error: el dominio $borrar no existe en el servidor"
    }
}
function MonitoreoDns {
    Write-Host "n=== MODULO DE MONITOREO Y VALIDACION ===" -ForegroundColor Cyan
    
   
    $servicio = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($servicio.Status -eq "Running") {
        Write-Host "[OK] El servicio DNS esta operando correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio DNS no esta iniciado." -ForegroundColor Red
        return
    }

 
    $dominioTest = Read-Host "Ingrese el dominio a validar (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominioTest)) { $dominioTest = "reprobados.com" }
    
    $hostTest = Read-Host "Ingrese el host a validar (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostTest)) { $hostTest = "www" }
    
    $nombreCompleto = "${hostTest}.${dominioTest}"

    Write-Host "nEjecutando nslookup para $nombreCompleto..." -ForegroundColor Yellow

    $lookup = Resolve-DnsName -Name $nombreCompleto -Server 127.0.0.1 -ErrorAction SilentlyContinue
    
    if ($lookup) {
        $ipDevuelta = $lookup.IPAddress
        Write-Host "[EXITO] nslookup resolvió $nombreCompleto en la IP: $ipDevuelta" -ForegroundColor Green
        
       
        Write-Host "Ejecutando ping para verificar respuesta..." -ForegroundColor Yellow
        $ping = Test-Connection -ComputerName $nombreCompleto -Count 1 -ErrorAction SilentlyContinue
        
        if ($ping) {
            $ipPing = $ping.IPV4Address.IPAddressToString
            Write-Host "[EXITO] Ping respondio desde $ipPing" -ForegroundColor Green
            
          
            if ($ipDevuelta -eq $ipPing) {
                Write-Host "EVIDENCIA: La IP devuelta coincide con la maquina referenciada ($ipDevuelta)." -ForegroundColor Cyan -BackgroundColor DarkBlue
            }
        } else {
            Write-Host "[AVISO] El nombre resuelve pero el host no responde al ping (verifique Firewall)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FALLO] No se pudo resolver el nombre $nombreCompleto en el DNS local." -ForegroundColor Red
    }
}
#do {
 #   Write-Host "n--- MENU DNS ---" -ForegroundColor Yellow
  #  Write-Host "[1] Verificar Instalacion"
   # Write-Host "[4] Configurar DNS"
    #Write-Host "Escriba 'salir' para finalizar."

    #$opc = Read-Host "nIngrese una opcion"

  #  switch($opc) {
   #     "1" { 
    #        if ((Get-WindowsFeature DNS).Installed) { Write-Host "Instalado" } else { Write-Host "No instalado" }
     #   }
      
      #  "4" { ConfigurarDns }
   # }
#} while ($opc -ne "salir")

do {
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "                           SERVIDOR DNS                               "
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "[1] - VERIFICAR INSTALACION DNS"
    Write-Host "[2] - INSTALAR SERVICIO DNS"
    Write-Host "[3] - REMOVER SERVICIO DNS"
    Write-Host "[4] - CONFIGURAR ZONA Y REGISTROS (reprobados.com)"
    write-Host "[5] - BORRAR DOMINIO"
    Write-Host "[6] - MONITOREO Y PRUEBAS"
    Write-Host "[7] - SALIR"

    $opc = Read-Host "nIngrese una opción"

    switch($opc) {
        "1" { 
            $v = Get-WindowsFeature DNS
            if ($v.Installed) { Write-Host "DNS Instalado" -ForegroundColor Green } else { Write-Host "No instalado" -ForegroundColor Red }
        }
        "2" { Install-WindowsFeature DNS -IncludeManagementTools }
        "3" { Uninstall-WindowsFeature DNS -Remove }
        "4" {
            ConfigurarDns
        }
        "5" { borrarDominio }
        "6" { MonitoreoDns }
        "7" { $opc = "salir" }
    }
} while ($opc -ne "salir")
Dame este codigo sin acentos porfavor


ChatGPT said:
Aquí tienes tu código sin acentos y sin caracteres especiales como ñ para evitar problemas de codificacion:

function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            return $ip
        }
        Write-Host "Formato IPv4 invalido. Reintente." -ForegroundColor Red
    } while ($true)
}

function GestionarIpFija {
    Write-Host "`n[Verificando Configuracion de Red]" -ForegroundColor Cyan
    $interfaz = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1
    
    if ($interfaz.Dhcp -eq "Enabled") {
        Write-Host "ADVERTENCIA: El servidor tiene DHCP habilitado. Se requiere IP fija para DNS." -ForegroundColor Yellow
        $nuevaIp = validacionIp "Ingrese la IP estatica para este servidor: "
        $mascara = Read-Host "Ingrese la mascara (ej. 24 para 255.255.255.0): "
        $gw = validacionIp "Ingrese el Gateway (Puerta de enlace): "
        
        Write-Host "Configurando IP estatica..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $interfaz.InterfaceAlias -IPAddress $nuevaIp -PrefixLength $mascara -DefaultGateway $gw
        Write-Host "IP configurada con exito." -ForegroundColor Green
    } else {
        $actual = (Get-NetIPAddress -InterfaceIndex $interfaz.InterfaceIndex -AddressFamily IPv4).IPAddress
        Write-Host "El servidor ya tiene una IP fija configurada: $actual" -ForegroundColor Green
    }
}

function ConfigurarDns {
    Write-Host "`n=== CONFIGURACION DE ZONA Y REGISTROS ===" -ForegroundColor Blue
    
    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

    $ipDestino = validacionIp "Ingrese la IP a la que apuntara ${hostname}.${dominio} : "

    try {
        if (-not (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
            Write-Host "Zona $dominio creada." -ForegroundColor Green
        }
        
        Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino -AllowUpdateAny
        Write-Host "Registro configurado con exito." -ForegroundColor Green
    } catch {
        Write-Host "Error en la configuracion: $($_.Exception.Message)" -ForegroundColor Red
    }
} 

function borrarDominio{
    $borrar = Read-Host "Ingrese el dominio que desea borrar (ej: reprobados.com)"
    if (Get-DnsServerZone -Name $borrar -ErrorAction SilentlyContinue){
        try{
            Remove-DnsServerZone -Name $borrar -Force
            Write-Host "El dominio $borrar ha sido borrado correctamente" -ForegroundColor Green
        } catch{
            Write-Host "Error al eliminar el dominio: $($_.Exception.Message)" -ForegroundColor Red
        }
    }else{
        Write-Host "Error: el dominio $borrar no existe en el servidor"
    }
}

function MonitoreoDns {
    Write-Host "`n=== MODULO DE MONITOREO Y VALIDACION ===" -ForegroundColor Cyan
    
    $servicio = Get-Service -Name DNS -ErrorAction SilentlyContinue
    if ($servicio.Status -eq "Running") {
        Write-Host "[OK] El servicio DNS esta operando correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El servicio DNS no esta iniciado." -ForegroundColor Red
        return
    }

    $dominioTest = Read-Host "Ingrese el dominio a validar (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominioTest)) { $dominioTest = "reprobados.com" }
    
    $hostTest = Read-Host "Ingrese el host a validar (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostTest)) { $hostTest = "www" }
    
    $nombreCompleto = "${hostTest}.${dominioTest}"

    Write-Host "`nEjecutando nslookup para $nombreCompleto..." -ForegroundColor Yellow

    $lookup = Resolve-DnsName -Name $nombreCompleto -Server 127.0.0.1 -ErrorAction SilentlyContinue
    
    if ($lookup) {
        $ipDevuelta = $lookup.IPAddress
        Write-Host "[EXITO] nslookup resolvio $nombreCompleto en la IP: $ipDevuelta" -ForegroundColor Green
        
        Write-Host "Ejecutando ping para verificar respuesta..." -ForegroundColor Yellow
        $ping = Test-Connection -ComputerName $nombreCompleto -Count 1 -ErrorAction SilentlyContinue
        
        if ($ping) {
            $ipPing = $ping.IPV4Address.IPAddressToString
            Write-Host "[EXITO] Ping respondio desde $ipPing" -ForegroundColor Green
            
            if ($ipDevuelta -eq $ipPing) {
                Write-Host "EVIDENCIA: La IP devuelta coincide con la maquina referenciada ($ipDevuelta)." -ForegroundColor Cyan -BackgroundColor DarkBlue
            }
        } else {
            Write-Host "[AVISO] El nombre resuelve pero el host no responde al ping (verifique Firewall)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[FALLO] No se pudo resolver el nombre $nombreCompleto en el DNS local." -ForegroundColor Red
    }
}

do {
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "                           SERVIDOR DNS                               "
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "[1] - VERIFICAR INSTALACION DNS"
    Write-Host "[2] - INSTALAR SERVICIO DNS"
    Write-Host "[3] - REMOVER SERVICIO DNS"
    Write-Host "[4] - CONFIGURAR ZONA Y REGISTROS (reprobados.com)"
    Write-Host "[5] - BORRAR DOMINIO"
    Write-Host "[6] - MONITOREO Y PRUEBAS"
    Write-Host "[7] - SALIR"

    $opc = Read-Host "`nIngrese una opcion"

    switch($opc) {
        "1" { 
            $v = Get-WindowsFeature DNS
            if ($v.Installed) { Write-Host "DNS Instalado" -ForegroundColor Green } else { Write-Host "No instalado" -ForegroundColor Red }
        }
        "2" { Install-WindowsFeature DNS -IncludeManagementTools }
        "3" { Uninstall-WindowsFeature DNS -Remove }
        "4" { ConfigurarDns }
        "5" { borrarDominio }
        "6" { MonitoreoDns }
        "7" { $opc = "salir" }
    }
} while ($opc -ne "salir")

You said:

set -eu


BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m' 
NC='\033[0m'


LAB_IFACE="eth1"
ZONEDIR="/var/bind"
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOCAL="/etc/bind/named.conf.local"


log(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
die(){ echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

require_root(){ [ "$(id -u)" -eq 0 ] || die "Ejecuta como root."; }


validacionIp() {
  while true; do
    printf "%s" "$1" >&2
    read -r ip || true
    if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
      echo "$ip"; return 0
    fi
    echo -e "${RED}Formato IPv4 inválido. Reintente.${NC}" >&2
  done
}

server_ip_eth1() {
  ip -4 addr show "$LAB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

verificar_ip_lab() {
  echo -e "${BLUE}================== VALIDACIÓN DE LAB ==================${NC}"
  ip link show "$LAB_IFACE" >/dev/null 2>&1 || die "No existe $LAB_IFACE."
  ip link set "$LAB_IFACE" up 2>/dev/null || true

  SIP="$(server_ip_eth1)"
  if [ -z "${SIP:-}" ]; then
    warn "eth1 NO tiene IP. Configura primero la red estática."
    return 1
  fi
  log "Servidor (eth1) tiene IP: $SIP"
  return 0
}


verificar_instalacion() {
  echo -e "${BLUE}>>> Verificando instalación DNS...${NC}"
  if command -v named >/dev/null 2>&1; then
    log "BIND instalado."
  else
    warn "BIND NO instalado."
  fi
}

instalar_dns() {
  echo -e "${BLUE}================== INSTALAR DNS ==================${NC}"
  if command -v named >/dev/null 2>&1; then
    log "BIND ya está instalado."
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || die "Falló la descarga."
  log "Instalación exitosa."
}

desinstalar_dns() {
  echo -e "${BLUE}================== DESINSTALAR DNS ==================${NC}"
  rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || die "Falló desinstalación."
  log "BIND eliminado del sistema."
}

asegurar_base_bind() {
  mkdir -p /etc/bind "$ZONEDIR"
  [ -f "$NAMED_LOCAL" ] || echo "// Zonas locales" > "$NAMED_LOCAL"
  if [ ! -f "$NAMED_CONF" ]; then
    cat > "$NAMED_CONF" <<EOF
options {
  directory "$ZONEDIR";
  listen-on { any; };
  allow-query { any; };
  recursion no;
};
include "$NAMED_LOCAL";
EOF
  fi
}

zona_existe() { grep -Eq "zone[[:space:]]+\"$1\"" "$NAMED_LOCAL" 2>/dev/null; }

listar_dominios() {
  echo -e "${BLUE}================== DOMINIOS ACTUALES ==================${NC}"
  [ -f "$NAMED_LOCAL" ] || { echo "(vacio)"; return 0; }
  awk -F\" '/zone "/{print " -> " $2}' "$NAMED_LOCAL" | sort -u
}

alta_dominio() {
  echo -e "${BLUE}================== ALTA DE DOMINIO ==================${NC}"
  verificar_ip_lab || return 1
  instalar_dns
  asegurar_base_bind

  printf "Nombre del dominio: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  IPDEST="$(validacionIp "IP de destino para $DOM: ")"
  ZFILE="$ZONEDIR/db.$DOM"

  if ! zona_existe "$DOM"; then
   
    echo "" >> "$NAMED_LOCAL"
    cat >> "$NAMED_LOCAL" <<EOF
zone "$DOM" {
    type master;
    file "$ZFILE";
};
EOF
    log "Zona $DOM agregada a named.conf.local"
  fi

 
  if [ ! -f "$ZFILE" ]; then
    SIP="$(server_ip_eth1)"
    cat > "$ZFILE" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. ( $(date +%Y%m%d)01 3600 900 1209600 3600 )
@   IN NS ns1.$DOM.
ns1 IN A  $SIP
@   IN A  $IPDEST
www IN A  $IPDEST
EOF
  fi

  if named-checkconf "$NAMED_CONF"; then
      rc-service named restart
      echo -e "${GREEN}ÉXITO: $DOM configurado y servicio reiniciado.${NC}"
  else
      echo -e "${RED}ERROR: Sintaxis inválida en $NAMED_LOCAL. Revisa el archivo.${NC}"
      return 1
  fi
}

baja_dominio() {
  echo -e "${BLUE}================== BAJA DE DOMINIO ==================${NC}"
  listar_dominios
  printf "Dominio a borrar: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  if zona_existe "$DOM"; then
    sed -i "/zone \"$DOM\"/,/};/d" "$NAMED_LOCAL"
    rm -f "$ZONEDIR/db.$DOM"
    rc-service named restart
    echo -e "${YELLOW}Dominio $DOM eliminado.${NC}"
  fi
}

estado_dns() {
  echo -e "${BLUE}================== ESTADO DNS ==================${NC}"
  rc-service named status 2>/dev/null || echo "Servicio detenido."
  listar_dominios
}


menu() {
  echo -e "\n${BLUE}====================================================${NC}"
  echo -e "${YELLOW}               SERVIDOR DNS - ALPINE                ${NC}"
  echo -e "${BLUE}====================================================${NC}"
  echo -e "${GREEN}[1]${NC} Verificar IP (eth1)"
  echo -e "${GREEN}[2]${NC} Verificar instalación"
  echo -e "${GREEN}[3]${NC} Instalar DNS"
  echo -e "${GREEN}[4]${NC} Desinstalar DNS"
  echo -e "${GREEN}[5]${NC} Listar dominios"
  echo -e "${GREEN}[6]${NC} Alta de dominio"
  echo -e "${GREEN}[7]${NC} Baja de dominio"
  echo -e "${GREEN}[8]${NC} Estado del servicio"
  echo -e "${GREEN}[9]${NC} Salir"
}


require_root
while true; do
  menu
  printf "\n${YELLOW}Seleccione una opción: ${NC}"
  read -r op

  case "$op" in
    1) verificar_ip_lab ;;
    2) verificar_instalacion ;;
    3) instalar_dns ;;
    4) desinstalar_dns ;;
    5) listar_dominios ;;
    6) alta_dominio ;;
    7) baja_dominio ;;
    8) estado_dns ;;
    9) exit 0 ;;
    *) echo "Opción no válida." ;;
  esac

  printf "\n${GREEN}¿Volver al menú? (si/no): ${NC}"
  read -r ch
  [ "$ch" = "si" ] || break
done

podrias darme este codigo pero que se vea un poco diferente sin alterar su funcionamiento y sin comas

ChatGPT said:
Aqui tienes tu script con el mismo funcionamiento pero con estructura visual un poco diferente nombres de colores distintos encabezados cambiados y sin usar comas adicionales

set -eu

CLR_AZUL='\033[1;34m'
CLR_AMARILLO='\033[1;33m'
CLR_VERDE='\033[0;32m'
CLR_ROJO='\033[0;31m'
CLR_OFF='\033[0m'

INTERFAZ_LAB="eth1"
DIR_ZONAS="/var/bind"
CONF_NAMED="/etc/bind/named.conf"
CONF_LOCAL="/etc/bind/named.conf.local"

info(){ echo -e "${CLR_VERDE}[OK]${CLR_OFF} $*"; }
aviso(){ echo -e "${CLR_AMARILLO}[AVISO]${CLR_OFF} $*"; }
error(){ echo -e "${CLR_ROJO}[ERROR]${CLR_OFF} $*"; exit 1; }

solo_root(){
  [ "$(id -u)" -eq 0 ] || error "Debes ejecutar como root"
}

validar_ip(){
  while true
  do
    printf "%s" "$1" >&2
    read -r ip || true
    if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    then
      echo "$ip"
      return 0
    fi
    echo -e "${CLR_ROJO}IPv4 invalida intenta nuevamente${CLR_OFF}" >&2
  done
}

obtener_ip_lab(){
  ip -4 addr show "$INTERFAZ_LAB" 2>/dev/null \
  | awk '/inet /{print $2}' \
  | head -n1 \
  | cut -d/ -f1 || true
}

validar_lab(){
  echo -e "${CLR_AZUL}========== VALIDACION LAB ==========${CLR_OFF}"
  ip link show "$INTERFAZ_LAB" >/dev/null 2>&1 || error "No existe $INTERFAZ_LAB"
  ip link set "$INTERFAZ_LAB" up 2>/dev/null || true

  IP_SERVIDOR="$(obtener_ip_lab)"
  if [ -z "${IP_SERVIDOR:-}" ]
  then
    aviso "La interfaz no tiene IP configurada"
    return 1
  fi

  info "IP detectada en $INTERFAZ_LAB -> $IP_SERVIDOR"
  return 0
}

verificar_dns(){
  echo -e "${CLR_AZUL}--- Verificando BIND ---${CLR_OFF}"
  if command -v named >/dev/null 2>&1
  then
    info "BIND instalado"
  else
    aviso "BIND no instalado"
  fi
}

instalar_dns(){
  echo -e "${CLR_AZUL}--- Instalacion DNS ---${CLR_OFF}"
  if command -v named >/dev/null 2>&1
  then
    info "BIND ya presente"
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || error "No se pudo instalar"
  info "Instalacion completada"
}

remover_dns(){
  echo -e "${CLR_AZUL}--- Eliminando DNS ---${CLR_OFF}"
  rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || error "Fallo al eliminar"
  info "BIND removido"
}

preparar_bind(){
  mkdir -p /etc/bind "$DIR_ZONAS"
  [ -f "$CONF_LOCAL" ] || echo "// zonas locales" > "$CONF_LOCAL"

  if [ ! -f "$CONF_NAMED" ]
  then
cat > "$CONF_NAMED" <<EOF
options {
  directory "$DIR_ZONAS";
  listen-on { any; };
  allow-query { any; };
  recursion no;
};
include "$CONF_LOCAL";
EOF
  fi
}

existe_zona(){
  grep -Eq "zone[[:space:]]+\"$1\"" "$CONF_LOCAL" 2>/dev/null
}

mostrar_dominios(){
  echo -e "${CLR_AZUL}========== DOMINIOS ==========${CLR_OFF}"
  [ -f "$CONF_LOCAL" ] || { echo "sin registros"; return 0; }
  awk -F\" '/zone "/{print " * " $2}' "$CONF_LOCAL" | sort -u
}

crear_dominio(){
  echo -e "${CLR_AZUL}========== NUEVO DOMINIO ==========${CLR_OFF}"
  validar_lab || return 1
  instalar_dns
  preparar_bind

  printf "Dominio: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  IP_DESTINO="$(validar_ip "IP destino para $DOM: ")"
  ARCHIVO_ZONA="$DIR_ZONAS/db.$DOM"

  if ! existe_zona "$DOM"
  then
    echo "" >> "$CONF_LOCAL"
cat >> "$CONF_LOCAL" <<EOF
zone "$DOM" {
  type master;
  file "$ARCHIVO_ZONA";
};
EOF
    info "Zona agregada en configuracion"
  fi

  if [ ! -f "$ARCHIVO_ZONA" ]
  then
    IP_LOCAL="$(obtener_ip_lab)"
cat > "$ARCHIVO_ZONA" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. ( $(date +%Y%m%d)01 3600 900 1209600 3600 )
@   IN NS ns1.$DOM.
ns1 IN A  $IP_LOCAL
@   IN A  $IP_DESTINO
www IN A  $IP_DESTINO
EOF
  fi

  if named-checkconf "$CONF_NAMED"
  then
    rc-service named restart
    echo -e "${CLR_VERDE}Dominio configurado correctamente${CLR_OFF}"
  else
    echo -e "${CLR_ROJO}Error de sintaxis revisar configuracion${CLR_OFF}"
    return 1
  fi
}

eliminar_dominio(){
  echo -e "${CLR_AZUL}========== ELIMINAR DOMINIO ==========${CLR_OFF}"
  mostrar_dominios
  printf "Dominio a eliminar: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  if existe_zona "$DOM"
  then
    sed -i "/zone \"$DOM\"/,/};/d" "$CONF_LOCAL"
    rm -f "$DIR_ZONAS/db.$DOM"
    rc-service named restart
    aviso "Dominio eliminado"
  fi
}

estado_servicio(){
  echo -e "${CLR_AZUL}========== ESTADO SERVICIO ==========${CLR_OFF}"
  rc-service named status 2>/dev/null || echo "Servicio detenido"
  mostrar_dominios
}

menu_principal(){
  echo -e "\n${CLR_AZUL}========================================${CLR_OFF}"
  echo -e "${CLR_AMARILLO}        DNS SERVER ALPINE LINUX        ${CLR_OFF}"
  echo -e "${CLR_AZUL}========================================${CLR_OFF}"
  echo -e "${CLR_VERDE}1${CLR_OFF} Validar IP"
  echo -e "${CLR_VERDE}2${CLR_OFF} Verificar DNS"
  echo -e "${CLR_VERDE}3${CLR_OFF} Instalar DNS"
  echo -e "${CLR_VERDE}4${CLR_OFF} Remover DNS"
  echo -e "${CLR_VERDE}5${CLR_OFF} Listar dominios"
  echo -e "${CLR_VERDE}6${CLR_OFF} Crear dominio"
  echo -e "${CLR_VERDE}7${CLR_OFF} Eliminar dominio"
  echo -e "${CLR_VERDE}8${CLR_OFF} Estado servicio"
  echo -e "${CLR_VERDE}9${CLR_OFF} Salir"
}

solo_root

while true
do
  menu_principal
  printf "\n${CLR_AMARILLO}Seleccion: ${CLR_OFF}"
  read -r opcion

  case "$opcion" in
    1) validar_lab ;;
    2) verificar_dns ;;
    3) instalar_dns ;;
    4) remover_dns ;;
    5) mostrar_dominios ;;
    6) crear_dominio ;;
    7) eliminar_dominio ;;
    8) estado_servicio ;;
    9) exit 0 ;;
    *) echo "Opcion invalida" ;;
  esac

  printf "\n${CLR_VERDE}Regresar al menu si no${CLR_OFF} "
  read -r resp
  [ "$resp" = "si" ] || break
done



