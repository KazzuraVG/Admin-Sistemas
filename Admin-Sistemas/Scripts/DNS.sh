#!/bin/sh
set -eu

# ┌─────────────────────────────────────────────────┐
# │         DNS MANAGER - Alpine Linux              │
# └─────────────────────────────────────────────────┘

C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_ORANGE='\033[0;33m'
C_GRAY='\033[0;90m'
NC='\033[0m'

LAB_IFACE="eth1"
ZONEDIR="/var/bind"
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOCAL="/etc/bind/named.conf.local"

DIVIDER="${C_GRAY}──────────────────────────────────────────────────${NC}"

log(){ echo -e "  ${C_GREEN}✔${NC}  $*"; }
warn(){ echo -e "  ${C_ORANGE}!${NC}  $*"; }
die(){ echo -e "  ${C_RED}✘${NC}  $*"; exit 1; }

require_root(){ [ "$(id -u)" -eq 0 ] || die "Ejecuta como root."; }

section() {
  echo -e "\n${DIVIDER}"
  echo -e "  ${C_CYAN}${1}${NC}"
  echo -e "${DIVIDER}"
}

validacionIp() {
  while true; do
    printf "  %s" "$1" >&2
    read -r ip || true
    if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
      echo "$ip"; return 0
    fi
    echo -e "  ${C_RED}IP invalida. Reintente.${NC}" >&2
  done
}

server_ip_eth1() {
  ip -4 addr show "$LAB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

verificar_ip_lab() {
  section "VALIDACION DE LAB"
  ip link show "$LAB_IFACE" >/dev/null 2>&1 || die "No existe $LAB_IFACE."
  ip link set "$LAB_IFACE" up 2>/dev/null || true

  SIP="$(server_ip_eth1)"
  if [ -z "${SIP:-}" ]; then
    warn "eth1 NO tiene IP. Configura primero la red estatica."
    return 1
  fi
  log "Servidor (eth1): $SIP"
  return 0
}

verificar_instalacion() {
  section "VERIFICAR INSTALACION"
  if command -v named >/dev/null 2>&1; then
    log "BIND instalado."
  else
    warn "BIND NO instalado."
  fi
}

instalar_dns() {
  section "INSTALAR DNS"
  if command -v named >/dev/null 2>&1; then
    log "BIND ya esta instalado."
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || die "Fallo la descarga."
  log "Instalacion exitosa."
}

desinstalar_dns() {
  section "DESINSTALAR DNS"
  rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || die "Fallo desinstalacion."
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
  section "DOMINIOS REGISTRADOS"
  [ -f "$NAMED_LOCAL" ] || { echo "  (sin dominios)"; return 0; }
  COUNT=0
  while IFS= read -r line; do
    echo -e "  ${C_CYAN}→${NC} $line"
    COUNT=$((COUNT + 1))
  done <<EOF
$(awk -F\" '/zone "/{print $2}' "$NAMED_LOCAL" | sort -u)
EOF
  [ "$COUNT" -eq 0 ] && echo "  (sin dominios)"
}

alta_dominio() {
  section "ALTA DE DOMINIO"
  verificar_ip_lab || return 1
  instalar_dns
  asegurar_base_bind

  printf "  Nombre del dominio: "
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
    log "Dominio $DOM configurado y servicio reiniciado."
  else
    die "Sintaxis invalida en $NAMED_LOCAL. Revisa el archivo."
    return 1
  fi
}

baja_dominio() {
  section "BAJA DE DOMINIO"
  listar_dominios
  printf "  Dominio a eliminar: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  if zona_existe "$DOM"; then
    sed -i "/zone \"$DOM\"/,/};/d" "$NAMED_LOCAL"
    rm -f "$ZONEDIR/db.$DOM"
    rc-service named restart
    warn "Dominio $DOM eliminado."
  else
    warn "El dominio $DOM no existe."
  fi
}

estado_dns() {
  section "ESTADO DEL SERVICIO"
  rc-service named status 2>/dev/null || echo "  Servicio detenido."
  listar_dominios
}

menu() {
  echo -e "\n${DIVIDER}"
  echo -e "  ${C_WHITE}DNS MANAGER${NC}  ${C_GRAY}Alpine Linux${NC}"
  echo -e "${DIVIDER}"
  echo -e "  ${C_CYAN}1${NC}  ${C_GRAY}│${NC}  Verificar IP (eth1)"
  echo -e "  ${C_CYAN}2${NC}  ${C_GRAY}│${NC}  Verificar instalacion"
  echo -e "  ${C_CYAN}3${NC}  ${C_GRAY}│${NC}  Instalar DNS"
  echo -e "  ${C_CYAN}4${NC}  ${C_GRAY}│${NC}  Desinstalar DNS"
  echo -e "  ${C_CYAN}5${NC}  ${C_GRAY}│${NC}  Listar dominios"
  echo -e "  ${C_CYAN}6${NC}  ${C_GRAY}│${NC}  Alta de dominio"
  echo -e "  ${C_CYAN}7${NC}  ${C_GRAY}│${NC}  Baja de dominio"
  echo -e "  ${C_CYAN}8${NC}  ${C_GRAY}│${NC}  Estado del servicio"
  echo -e "  ${C_CYAN}9${NC}  ${C_GRAY}│${NC}  Salir"
  echo -e "${DIVIDER}"
}

require_root
while true; do
  menu
  printf "  ${C_WHITE}Opcion:${NC} "
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
    *) warn "Opcion no valida." ;;
  esac

  printf "\n  ${C_GREEN}Volver al menu? (si/no):${NC} "
  read -r ch
  [ "$ch" = "si" ] || break
done