

#!/bin/sh
set -eu

# ===== COLORES =====
C1='\033[1;36m'
C2='\033[1;35m'
C3='\033[1;32m'
C4='\033[1;31m'
END='\033[0m'

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m' 
NC='\033[0m'


LAB_IFACE="eth1"
ZONEDIR="/var/bind"
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOCAL="/etc/bind/named.conf.local"

# ===== VARIABLES =====
IF_LAB="eth1"
DIR_ZONAS="/var/bind"
CONF_MAIN="/etc/bind/named.conf"
CONF_LOCAL="/etc/bind/named.conf.local"

log(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
die(){ echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
ok(){ echo -e "${C3}[OK]${END} $*"; }
warn(){ echo -e "${C2}[WARN]${END} $*"; }
fail(){ echo -e "${C4}[ERROR]${END} $*"; exit 1; }

require_root(){ [ "$(id -u)" -eq 0 ] || die "Ejecuta como root."; }
check_root(){ [ "$(id -u)" -eq 0 ] || fail "Ejecutar como root."; }


validacionIp() {
validar_ip() {
while true; do
printf "%s" "$1" >&2
read -r ip || true
if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
echo "$ip"; return 0
fi
    echo -e "${RED}Formato IPv4 inválido. Reintente.${NC}" >&2
    echo -e "${C4}IP invalida.${END}" >&2
done
}

server_ip_eth1() {
  ip -4 addr show "$LAB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
obtener_ip() {
  ip -4 addr show "$IF_LAB" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

verificar_ip_lab() {
  echo -e "${BLUE}================== VALIDACIÓN DE LAB ==================${NC}"
  ip link show "$LAB_IFACE" >/dev/null 2>&1 || die "No existe $LAB_IFACE."
  ip link set "$LAB_IFACE" up 2>/dev/null || true
verificar_red() {
  echo -e "${C1}========== VALIDANDO RED ==========${END}"
  ip link show "$IF_LAB" >/dev/null 2>&1 || fail "No existe $IF_LAB"
  ip link set "$IF_LAB" up 2>/dev/null || true

  SIP="$(server_ip_eth1)"
  if [ -z "${SIP:-}" ]; then
    warn "eth1 NO tiene IP. Configura primero la red estática."
  IP_ACTUAL="$(obtener_ip)"
  if [ -z "${IP_ACTUAL:-}" ]; then
    warn "Sin IP en $IF_LAB"
return 1
fi
  log "Servidor (eth1) tiene IP: $SIP"
  return 0
  ok "IP detectada: $IP_ACTUAL"
}


verificar_instalacion() {
  echo -e "${BLUE}>>> Verificando instalación DNS...${NC}"
verificar_dns() {
  echo -e "${C1}Verificando servicio DNS...${END}"
if command -v named >/dev/null 2>&1; then
    log "BIND instalado."
    ok "Servicio instalado."
else
    warn "BIND NO instalado."
    warn "Servicio no instalado."
fi
}

instalar_dns() {
  echo -e "${BLUE}================== INSTALAR DNS ==================${NC}"
  echo -e "${C1}Instalando servicio DNS...${END}"
if command -v named >/dev/null 2>&1; then
    log "BIND ya está instalado."
    ok "Ya esta instalado."
return 0
fi
  apk add --no-cache bind bind-tools bind-openrc || die "Falló la descarga."
  log "Instalación exitosa."
  apk add --no-cache bind bind-tools bind-openrc || fail "Error en instalacion."
  ok "Instalacion completada."
}

desinstalar_dns() {
  echo -e "${BLUE}================== DESINSTALAR DNS ==================${NC}"
eliminar_dns() {
  echo -e "${C1}Eliminando servicio DNS...${END}"
rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || die "Falló desinstalación."
  log "BIND eliminado del sistema."
  apk del bind bind-tools bind-openrc || fail "Error al desinstalar."
  ok "Servicio eliminado."
}

asegurar_base_bind() {
  mkdir -p /etc/bind "$ZONEDIR"
  [ -f "$NAMED_LOCAL" ] || echo "// Zonas locales" > "$NAMED_LOCAL"
  if [ ! -f "$NAMED_CONF" ]; then
    cat > "$NAMED_CONF" <<EOF
config_base() {
  mkdir -p /etc/bind "$DIR_ZONAS"
  [ -f "$CONF_LOCAL" ] || echo "// Configuracion local" > "$CONF_LOCAL"
  if [ ! -f "$CONF_MAIN" ]; then
    cat > "$CONF_MAIN" <<EOF
options {
  directory "$ZONEDIR";
  directory "$DIR_ZONAS";
 listen-on { any; };
 allow-query { any; };
 recursion no;
};
include "$NAMED_LOCAL";
include "$CONF_LOCAL";
EOF
fi
}

zona_existe() { grep -Eq "zone[[:space:]]+\"$1\"" "$NAMED_LOCAL" 2>/dev/null; }
zona_existe(){ grep -Eq "zone[[:space:]]+\"$1\"" "$CONF_LOCAL" 2>/dev/null; }

listar_dominios() {
  echo -e "${BLUE}================== DOMINIOS ACTUALES ==================${NC}"
  [ -f "$NAMED_LOCAL" ] || { echo "(vacio)"; return 0; }
  awk -F\" '/zone "/{print " -> " $2}' "$NAMED_LOCAL" | sort -u
  echo -e "${C1}======= DOMINIOS CONFIGURADOS =======${END}"
  [ -f "$CONF_LOCAL" ] || { echo "(sin dominios)"; return; }
  awk -F\" '/zone "/{print " - " $2}' "$CONF_LOCAL" | sort -u
}

alta_dominio() {
  echo -e "${BLUE}================== ALTA DE DOMINIO ==================${NC}"
  verificar_ip_lab || return 1
crear_dominio() {
  echo -e "${C1}======= CREAR DOMINIO =======${END}"
  verificar_red || return 1
instalar_dns
  asegurar_base_bind
  config_base

  printf "Nombre del dominio: "
  printf "Dominio: "
read -r DOM
[ -n "${DOM:-}" ] || return 1

  IPDEST="$(validacionIp "IP de destino para $DOM: ")"
  ZFILE="$ZONEDIR/db.$DOM"
  IP_DEST="$(validar_ip "IP destino: ")"
  ARCH_ZONA="$DIR_ZONAS/db.$DOM"

if ! zona_existe "$DOM"; then
   
    echo "" >> "$NAMED_LOCAL"
    cat >> "$NAMED_LOCAL" <<EOF
    echo "" >> "$CONF_LOCAL"
    cat >> "$CONF_LOCAL" <<EOF
zone "$DOM" {
   type master;
    file "$ZFILE";
    file "$ARCH_ZONA";
};
EOF
    log "Zona $DOM agregada a named.conf.local"
fi

 
  if [ ! -f "$ZFILE" ]; then
    SIP="$(server_ip_eth1)"
    cat > "$ZFILE" <<EOF
  if [ ! -f "$ARCH_ZONA" ]; then
    IP_SERV="$(obtener_ip)"
    cat > "$ARCH_ZONA" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. ( $(date +%Y%m%d)01 3600 900 1209600 3600 )
@   IN NS ns1.$DOM.
ns1 IN A  $SIP
@   IN A  $IPDEST
www IN A  $IPDEST
ns1 IN A  $IP_SERV
@   IN A  $IP_DEST
www IN A  $IP_DEST
EOF
fi

  if named-checkconf "$NAMED_CONF"; then
  if named-checkconf "$CONF_MAIN"; then
rc-service named restart
      echo -e "${GREEN}ÉXITO: $DOM configurado y servicio reiniciado.${NC}"
      ok "Dominio $DOM activo."
else
      echo -e "${RED}ERROR: Sintaxis inválida en $NAMED_LOCAL. Revisa el archivo.${NC}"
      echo -e "${C4}Error en configuracion.${END}"
return 1
fi
}

baja_dominio() {
  echo -e "${BLUE}================== BAJA DE DOMINIO ==================${NC}"
eliminar_dominio() {
  echo -e "${C1}======= ELIMINAR DOMINIO =======${END}"
listar_dominios
  printf "Dominio a borrar: "
  printf "Dominio a eliminar: "
read -r DOM
[ -n "${DOM:-}" ] || return 1

if zona_existe "$DOM"; then
    sed -i "/zone \"$DOM\"/,/};/d" "$NAMED_LOCAL"
    rm -f "$ZONEDIR/db.$DOM"
    sed -i "/zone \"$DOM\"/,/};/d" "$CONF_LOCAL"
    rm -f "$DIR_ZONAS/db.$DOM"
rc-service named restart
    echo -e "${YELLOW}Dominio $DOM eliminado.${NC}"
    warn "Dominio eliminado."
fi
}

estado_dns() {
  echo -e "${BLUE}================== ESTADO DNS ==================${NC}"
estado_servicio() {
  echo -e "${C1}======= ESTADO DEL SERVICIO =======${END}"
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
  clear
  echo -e "${C2}"
  echo "====================================="
  echo "         PANEL DNS ALPINE"
  echo "====================================="
  echo " 1) Verificar red"
  echo " 2) Verificar instalacion"
  echo " 3) Instalar DNS"
  echo " 4) Eliminar DNS"
  echo " 5) Listar dominios"
  echo " 6) Crear dominio"
  echo " 7) Eliminar dominio"
  echo " 8) Estado del servicio"
  echo " 9) Salir"
  echo "====================================="
  echo -e "${END}"
}


require_root
check_root
while true; do
menu
  printf "\n${YELLOW}Seleccione una opción: ${NC}"
  printf "Selecciona opcion: "
read -r op

case "$op" in
    1) verificar_ip_lab ;;
    2) verificar_instalacion ;;
    1) verificar_red ;;
    2) verificar_dns ;;
3) instalar_dns ;;
    4) desinstalar_dns ;;
    4) eliminar_dns ;;
5) listar_dominios ;;
    6) alta_dominio ;;
    7) baja_dominio ;;
    8) estado_dns ;;
    6) crear_dominio ;;
    7) eliminar_dominio ;;
    8) estado_servicio ;;
9) exit 0 ;;
    *) echo "Opción no válida." ;;
    *) echo "Opcion invalida." ;;
esac

  printf "\n${GREEN}¿Volver al menú? (si/no): ${NC}"
  read -r ch
  [ "$ch" = "si" ] || break
done
  printf "\nPresiona ENTER para continuar..."
  read
done