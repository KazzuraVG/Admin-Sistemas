#!/bin/sh
set -eu

# ===== COLORES =====
C1='\033[1;36m'
C2='\033[1;35m'
C3='\033[1;32m'
C4='\033[1;31m'
END='\033[0m'

# ===== VARIABLES =====
IF_LAB="eth1"
DIR_ZONAS="/var/bind"
CONF_MAIN="/etc/bind/named.conf"
CONF_LOCAL="/etc/bind/named.conf.local"

ok(){ echo -e "${C3}[OK]${END} $*"; }
warn(){ echo -e "${C2}[WARN]${END} $*"; }
fail(){ echo -e "${C4}[ERROR]${END} $*"; exit 1; }

check_root(){ [ "$(id -u)" -eq 0 ] || fail "Ejecutar como root."; }

validar_ip() {
  while true; do
    printf "%s" "$1" >&2
    read -r ip || true
    if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
      echo "$ip"; return 0
    fi
    echo -e "${C4}IP invalida.${END}" >&2
  done
}

obtener_ip() {
  ip -4 addr show "$IF_LAB" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

verificar_red() {
  echo -e "${C1}========== VALIDANDO RED ==========${END}"
  ip link show "$IF_LAB" >/dev/null 2>&1 || fail "No existe $IF_LAB"
  ip link set "$IF_LAB" up 2>/dev/null || true

  IP_ACTUAL="$(obtener_ip)"
  if [ -z "${IP_ACTUAL:-}" ]; then
    warn "Sin IP en $IF_LAB"
    return 1
  fi
  ok "IP detectada: $IP_ACTUAL"
}

verificar_dns() {
  echo -e "${C1}Verificando servicio DNS...${END}"
  if command -v named >/dev/null 2>&1; then
    ok "Servicio instalado."
  else
    warn "Servicio no instalado."
  fi
}

instalar_dns() {
  echo -e "${C1}Instalando servicio DNS...${END}"
  if command -v named >/dev/null 2>&1; then
    ok "Ya esta instalado."
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || fail "Error en instalacion."
  ok "Instalacion completada."
}

eliminar_dns() {
  echo -e "${C1}Eliminando servicio DNS...${END}"
  rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || fail "Error al desinstalar."
  ok "Servicio eliminado."
}

config_base() {
  mkdir -p /etc/bind "$DIR_ZONAS"
  [ -f "$CONF_LOCAL" ] || echo "// Configuracion local" > "$CONF_LOCAL"
  if [ ! -f "$CONF_MAIN" ]; then
    cat > "$CONF_MAIN" <<EOF
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

zona_existe(){ grep -Eq "zone[[:space:]]+\"$1\"" "$CONF_LOCAL" 2>/dev/null; }

listar_dominios() {
  echo -e "${C1}======= DOMINIOS CONFIGURADOS =======${END}"
  [ -f "$CONF_LOCAL" ] || { echo "(sin dominios)"; return; }
  awk -F\" '/zone "/{print " - " $2}' "$CONF_LOCAL" | sort -u
}

crear_dominio() {
  echo -e "${C1}======= CREAR DOMINIO =======${END}"
  verificar_red || return 1
  instalar_dns
  config_base

  printf "Dominio: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  IP_DEST="$(validar_ip "IP destino: ")"
  ARCH_ZONA="$DIR_ZONAS/db.$DOM"

  if ! zona_existe "$DOM"; then
    echo "" >> "$CONF_LOCAL"
    cat >> "$CONF_LOCAL" <<EOF
zone "$DOM" {
    type master;
    file "$ARCH_ZONA";
};
EOF
  fi

  if [ ! -f "$ARCH_ZONA" ]; then
    IP_SERV="$(obtener_ip)"
    cat > "$ARCH_ZONA" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. ( $(date +%Y%m%d)01 3600 900 1209600 3600 )
@   IN NS ns1.$DOM.
ns1 IN A  $IP_SERV
@   IN A  $IP_DEST
www IN A  $IP_DEST
EOF
  fi

  if named-checkconf "$CONF_MAIN"; then
      rc-service named restart
      ok "Dominio $DOM activo."
  else
      echo -e "${C4}Error en configuracion.${END}"
      return 1
  fi
}

eliminar_dominio() {
  echo -e "${C1}======= ELIMINAR DOMINIO =======${END}"
  listar_dominios
  printf "Dominio a eliminar: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  if zona_existe "$DOM"; then
    sed -i "/zone \"$DOM\"/,/};/d" "$CONF_LOCAL"
    rm -f "$DIR_ZONAS/db.$DOM"
    rc-service named restart
    warn "Dominio eliminado."
  fi
}

estado_servicio() {
  echo -e "${C1}======= ESTADO DEL SERVICIO =======${END}"
  rc-service named status 2>/dev/null || echo "Servicio detenido."
  listar_dominios
}

menu() {
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

check_root
while true; do
  menu
  printf "Selecciona opcion: "
  read -r op

  case "$op" in
    1) verificar_red ;;
    2) verificar_dns ;;
    3) instalar_dns ;;
    4) eliminar_dns ;;
    5) listar_dominios ;;
    6) crear_dominio ;;
    7) eliminar_dominio ;;
    8) estado_servicio ;;
    9) exit 0 ;;
    *) echo "Opcion invalida." ;;
  esac

  printf "\nPresiona ENTER para continuar..."
  read
done