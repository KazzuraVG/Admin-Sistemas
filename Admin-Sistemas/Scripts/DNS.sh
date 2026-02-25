#!/bin/sh
set -eu

# ╔════════════════════════════════════════════════════╗
# ║          BIND9 CONTROL PANEL :: Alpine             ║
# ╚════════════════════════════════════════════════════╝

#── Colores ────────────────────────────────────────────
K_OK='\033[0;32m'
K_NG='\033[0;31m'
K_WR='\033[0;33m'
K_HI='\033[1;36m'
K_DM='\033[0;90m'
K_BD='\033[1;37m'
K_RS='\033[0m'

#── Rutas ──────────────────────────────────────────────
NIC="eth1"
ZONE_DIR="/var/bind"
CONF_MAIN="/etc/bind/named.conf"
CONF_ZONES="/etc/bind/named.conf.local"

#── Utilidades ─────────────────────────────────────────
ok()   { printf "  ${K_OK}[OK]${K_RS}  %s\n" "$*"; }
fail() { printf "  ${K_NG}[!!]${K_RS}  %s\n" "$*"; exit 1; }
note() { printf "  ${K_WR}[--]${K_RS}  %s\n" "$*"; }

box() {
  local title="$1"
  printf "\n${K_DM}  ┌──────────────────────────────────────────────┐${K_RS}\n"
  printf   "${K_HI}  │  %-44s│${K_RS}\n" "$title"
  printf   "${K_DM}  └──────────────────────────────────────────────┘${K_RS}\n\n"
}

ask() {
  printf "  ${K_BD}▸${K_RS} %s " "$1"
  read -r REPLY
  echo "$REPLY"
}

need_root() {
  [ "$(id -u)" -eq 0 ] || fail "Se requiere root."
}

#── Red ────────────────────────────────────────────────
get_server_ip() {
  ip -4 addr show "$NIC" 2>/dev/null \
    | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

validar_ipv4() {
  local prompt="$1" addr
  while true; do
    printf "  ${K_BD}▸${K_RS} %s " "$prompt" >&2
    read -r addr || true
    if echo "$addr" | grep -Eq \
      '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    then
      echo "$addr"; return 0
    fi
    printf "  ${K_NG}IP no valida. Intente de nuevo.${K_RS}\n" >&2
  done
}

chequear_red() {
  box "VERIFICACION DE RED"
  ip link show "$NIC" >/dev/null 2>&1 || fail "Interfaz $NIC no encontrada."
  ip link set "$NIC" up 2>/dev/null || true
  local addr
  addr="$(get_server_ip)"
  if [ -z "${addr:-}" ]; then
    note "$NIC no tiene IP asignada."
    return 1
  fi
  ok "$NIC activa con IP: $addr"
}

#── BIND ───────────────────────────────────────────────
chequear_bind() {
  box "ESTADO DE INSTALACION"
  if command -v named >/dev/null 2>&1; then
    ok "BIND9 esta instalado."
  else
    note "BIND9 no esta instalado."
  fi
}

instalar_bind() {
  box "INSTALAR BIND9"
  if command -v named >/dev/null 2>&1; then
    ok "BIND9 ya estaba instalado."
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || fail "Error al instalar."
  ok "BIND9 instalado correctamente."
}

desinstalar_bind() {
  box "DESINSTALAR BIND9"
  rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || fail "Error al desinstalar."
  ok "BIND9 eliminado del sistema."
}

preparar_conf() {
  mkdir -p /etc/bind "$ZONE_DIR"
  [ -f "$CONF_ZONES" ] || echo "// zonas locales" > "$CONF_ZONES"
  if [ ! -f "$CONF_MAIN" ]; then
    cat > "$CONF_MAIN" <<EOF
options {
  directory "$ZONE_DIR";
  listen-on { any; };
  allow-query { any; };
  recursion no;
};
include "$CONF_ZONES";
EOF
  fi
}

zona_registrada() {
  grep -Eq "zone[[:space:]]+\"$1\"" "$CONF_ZONES" 2>/dev/null
}

#── Dominios ───────────────────────────────────────────
listar_zonas() {
  box "ZONAS CONFIGURADAS"
  [ -f "$CONF_ZONES" ] || { note "Sin zonas registradas."; return 0; }
  local found=0
  while IFS= read -r entry; do
    printf "  ${K_HI}◆${K_RS}  %s\n" "$entry"
    found=$((found + 1))
  done <<ZEOF
$(awk -F'"' '/zone "/{print $2}' "$CONF_ZONES" | sort -u)
ZEOF
  [ "$found" -gt 0 ] || note "Sin zonas registradas."
}

agregar_zona() {
  box "REGISTRAR DOMINIO"
  chequear_red || return 1
  instalar_bind
  preparar_conf

  DOM="$(ask "Nombre del dominio:")"
  [ -n "${DOM:-}" ] || return 1

  TARGET_IP="$(validar_ipv4 "IP de destino para $DOM:")"
  ZONE_FILE="$ZONE_DIR/db.$DOM"

  if ! zona_registrada "$DOM"; then
    {
      echo ""
      echo "zone \"$DOM\" {"
      echo "    type master;"
      echo "    file \"$ZONE_FILE\";"
      echo "};"
    } >> "$CONF_ZONES"
    ok "Zona $DOM agregada."
  fi

  if [ ! -f "$ZONE_FILE" ]; then
    SRV_IP="$(get_server_ip)"
    cat > "$ZONE_FILE" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. ( $(date +%Y%m%d)01 3600 900 1209600 3600 )
@   IN NS  ns1.$DOM.
ns1 IN A   $SRV_IP
@   IN A   $TARGET_IP
www IN A   $TARGET_IP
EOF
  fi

  if named-checkconf "$CONF_MAIN"; then
    rc-service named restart
    ok "Dominio $DOM activo. Servicio reiniciado."
  else
    fail "Configuracion invalida. Revisa $CONF_ZONES"
    return 1
  fi
}

eliminar_zona() {
  box "ELIMINAR DOMINIO"
  listar_zonas
  DOM="$(ask "Dominio a eliminar:")"
  [ -n "${DOM:-}" ] || return 1

  if zona_registrada "$DOM"; then
    sed -i "/zone \"$DOM\"/,/};/d" "$CONF_ZONES"
    rm -f "$ZONE_DIR/db.$DOM"
    rc-service named restart
    note "Dominio $DOM eliminado."
  else
    note "El dominio $DOM no existe."
  fi
}

estado_servicio() {
  box "ESTADO DEL SERVICIO"
  rc-service named status 2>/dev/null || note "Servicio detenido."
  listar_zonas
}

#── Menu ───────────────────────────────────────────────
mostrar_menu() {
  printf "\n${K_DM}  ╔══════════════════════════════════════════════╗${K_RS}\n"
  printf   "${K_BD}  ║        BIND9 CONTROL PANEL :: Alpine        ║${K_RS}\n"
  printf   "${K_DM}  ╠══════════════════════════════════════════════╣${K_RS}\n"
  printf   "  ║  ${K_HI}1${K_RS}  Verificar red           ${K_HI}6${K_RS}  Alta de zona  ${K_DM}║${K_RS}\n"
  printf   "  ║  ${K_HI}2${K_RS}  Estado BIND             ${K_HI}7${K_RS}  Baja de zona  ${K_DM}║${K_RS}\n"
  printf   "  ║  ${K_HI}3${K_RS}  Instalar BIND           ${K_HI}8${K_RS}  Estado DNS    ${K_DM}║${K_RS}\n"
  printf   "  ║  ${K_HI}4${K_RS}  Desinstalar BIND        ${K_HI}9${K_RS}  Salir         ${K_DM}║${K_RS}\n"
  printf   "  ║  ${K_HI}5${K_RS}  Listar zonas                          ${K_DM}║${K_RS}\n"
  printf   "${K_DM}  ╚══════════════════════════════════════════════╝${K_RS}\n"
}

#── Main ───────────────────────────────────────────────
need_root

while true; do
  mostrar_menu
  printf "\n  ${K_BD}▸${K_RS} Seleccione: "
  read -r OPCION

  case "$OPCION" in
    1) chequear_red ;;
    2) chequear_bind ;;
    3) instalar_bind ;;
    4) desinstalar_bind ;;
    5) listar_zonas ;;
    6) agregar_zona ;;
    7) eliminar_zona ;;
    8) estado_servicio ;;
    9) printf "\n  ${K_DM}Saliendo...${K_RS}\n\n"; exit 0 ;;
    *) note "Opcion no reconocida." ;;
  esac

  printf "\n  ${K_WR}▸${K_RS} Volver al menu? (si/no): "
  read -r CONTINUAR
  [ "$CONTINUAR" = "si" ] || break
done
