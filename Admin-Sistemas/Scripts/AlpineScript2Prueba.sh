#!/bin/sh

# =====================================================
#         SCRIPT DE GESTION KEA DHCP - ALPINE
# =====================================================

# -------- COLORES --------
C_BLUE='\033[0;34m'
C_YELLOW='\033[1;33m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_PURPLE='\033[0;35m'
C_WHITE='\033[0;37m'
C_RESET='\033[0m'

echo -e "${C_BLUE}=================================================${C_RESET}"
echo -e "${C_YELLOW}=========== SISTEMA DHCP KEA (ALPINE) ==========${C_RESET}"
echo -e "${C_BLUE}=================================================${C_RESET}"

# =====================================================
# FUNCION VALIDACION IPV4
# =====================================================

validar_ip() {
    texto="$1"
    permitir_vacio="$2"

    while true; do
        printf "${C_CYAN}%s${C_RESET}" "$texto" >&2
        read entrada

        if [ "$permitir_vacio" = "true" ] && [ -z "$entrada" ]; then
            echo ""
            return 0
        fi

        if echo "$entrada" | grep -E -q '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then

            if echo "$entrada" | grep -q '\.0[0-9]'; then
                echo -e "${C_RED}error: no se permiten ceros a la izquierda${C_RESET}" >&2
                continue
            fi

            octeto1=$(echo "$entrada" | cut -d. -f1)

            if [ "$entrada" = "0.0.0.0" ]; then
                echo -e "${C_RED}error: direccion reservada${C_RESET}" >&2
            elif [ "$entrada" = "255.255.255.255" ]; then
                echo -e "${C_RED}error: broadcast global${C_RESET}" >&2
            elif [ "$octeto1" -eq 127 ]; then
                echo -e "${C_RED}error: rango loopback${C_RESET}" >&2
            elif [ "$octeto1" -ge 224 ]; then
                echo -e "${C_RED}error: rango multicast o reservado${C_RESET}" >&2
            else
                echo "$entrada"
                return 0
            fi
        else
            echo -e "${C_RED}formato ipv4 invalido, intente nuevamente${C_RESET}" >&2
        fi
    done
}

# =====================================================
# FUNCIONES DEL SISTEMA
# =====================================================

estado_servicio() {
    echo -e "${C_YELLOW}Revisando instalacion de kea-dhcp4...${C_RESET}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${C_GREEN}Servicio kea-dhcp4 presente${C_RESET}"
    else
        echo -e "${C_RED}Servicio no instalado${C_RESET}"
    fi
}

instalar_servicio() {
    echo -e "${C_CYAN}Proceso de instalacion iniciado...${C_RESET}"

    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${C_GREEN}El servicio ya esta instalado${C_RESET}"
    else
        apk add kea-dhcp4
        if [ $? -eq 0 ]; then
            mkdir -p /var/lib/kea
            echo -e "${C_GREEN}Instalacion completada correctamente${C_RESET}"
        else
            echo -e "${C_RED}Error durante la instalacion${C_RESET}"
        fi
    fi
}

eliminar_servicio() {
    echo -e "${C_PURPLE}Iniciando eliminacion del servicio...${C_RESET}"

    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        rc-service kea-dhcp4 stop 2>/dev/null
        apk del kea-dhcp4
        echo -e "${C_GREEN}Servicio eliminado${C_RESET}"
    else
        echo -e "${C_RED}No existe instalacion previa${C_RESET}"
    fi
}

# =====================================================
# CONFIGURACION DHCP
# =====================================================

configurar_dhcp() {

    echo -e "${C_BLUE}==== CONFIGURACION KEA DHCP ====${C_RESET}"

    printf "Nombre del scope: "
    read scopeNombre

    ipServidor=$(validar_ip "IP fija del servidor (eth1): ")
    redBase=$(echo "$ipServidor" | cut -d. -f1-3)
    ultimoOcteto=$(echo "$ipServidor" | cut -d. -f4)

    ip addr add $ipServidor/24 dev eth1 2>/dev/null
    ip link set eth1 up 2>/dev/null

    inicioPool="$redBase.$((ultimoOcteto + 1))"

    while true; do
        ipFinal=$(validar_ip "IP final del rango: ")
        redFinal=$(echo "$ipFinal" | cut -d. -f1-3)
        ultimoFinal=$(echo "$ipFinal" | cut -d. -f4)

        if [ "$ultimoOcteto" -ge "$ultimoFinal" ]; then
            echo -e "${C_RED}La IP inicial no puede ser mayor que la final${C_RESET}"
        elif [ "$redBase" != "$redFinal" ]; then
            echo -e "${C_RED}Ambas IP deben pertenecer a la misma subred${C_RESET}"
        else
            redID="$redBase.0"
            break
        fi
    done

    dnsServer=$(validar_ip "Servidor DNS (default 8.8.8.8): " true)
    [ -z "$dnsServer" ] && dnsServer="8.8.8.8"

    printf "Gateway (opcional): "
    read gatewayIP

    printf "Tiempo de lease en segundos (default 28800): "
    read leaseTime
    [ -z "$leaseTime" ] && leaseTime="28800"

    EXTRA_ROUTER=""
    if [ -n "$gatewayIP" ]; then
        EXTRA_ROUTER=", { \"name\": \"routers\", \"data\": \"$gatewayIP\" }"
    fi

cat <<EOF > /etc/kea/kea-dhcp4.conf
{
"Dhcp4": {
    "interfaces-config": { "interfaces": [ "eth1" ] },
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases4.csv"
    },
    "valid-lifetime": $leaseTime,
    "subnet4": [
        {
            "id": 1,
            "subnet": "$redID/24",
            "pools": [ { "pool": "$inicioPool - $ipFinal" } ],
            "option-data": [
                { "name": "domain-name-servers", "data": "$dnsServer" }$EXTRA_ROUTER
            ]
        }
    ]
}
}
EOF

    rc-service kea-dhcp4 restart
    rc-update add kea-dhcp4 default

    echo -e "${C_GREEN}Configuracion aplicada para: $scopeNombre${C_RESET}"
}

# =====================================================
# MONITOREO
# =====================================================

ver_estado() {
    echo -e "${C_BLUE}========== ESTADO DEL SERVICIO ==========${C_RESET}"

    if rc-service kea-dhcp4 status | grep -q "started"; then
        echo -e "Servicio: ${C_GREEN}Running${C_RESET}"
    else
        echo -e "${C_RED}Servicio detenido${C_RESET}"
        return
    fi

    echo -e "${C_YELLOW}Leases actuales:${C_RESET}"

    if [ -f /var/lib/kea/kea-leases4.csv ]; then
        column -t -s ',' /var/lib/kea/kea-leases4.csv
    else
        echo -e "${C_WHITE}Sin leases registrados${C_RESET}"
    fi
}

# =====================================================
# MENU PRINCIPAL
# =====================================================

menu_principal() {
    echo -e "${C_BLUE}============== MENU ==============${C_RESET}"
    echo "1) Verificar instalacion"
    echo "2) Instalar servicio"
    echo "3) Desinstalar servicio"
    echo "4) Configurar DHCP"
    echo "5) Monitoreo"
    echo "6) Salir"
}

# =====================================================
# LOOP
# =====================================================

while true; do

    menu_principal
    printf "Seleccione opcion: "
    read opcion

    case $opcion in
        1) estado_servicio ;;
        2) instalar_servicio ;;
        3) eliminar_servicio ;;
        4) configurar_dhcp ;;
        5) ver_estado ;;
        6) exit 0 ;;
        *) echo -e "${C_RED}Opcion no valida${C_RESET}" ;;
    esac

    printf "\nVolver al menu? (si/no): "
    read volver
    [ "$volver" != "si" ] && break

done