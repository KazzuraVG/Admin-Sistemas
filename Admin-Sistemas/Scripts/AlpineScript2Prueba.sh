#!/bin/sh
# =====================================================
#    Automatización DHCP - Alpine Linux
# =====================================================

# -------- Colores ----------
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[1;34m'
N='\033[0m'

CONFIG="/etc/dhcp/dhcpd.conf"
LEASES="/var/lib/dhcp/dhcpd.leases"

# -----------------------------------------------------
mostrar_ayuda() {
    echo "Uso: $0 [opcion]"
    echo ""
    echo -e " ${B}-check${N}        Verificar instalación"
    echo -e " ${B}-install${N}      Instalar DHCP"
    echo -e " ${B}-start${N}        Iniciar servicio"
    echo -e " ${B}-restart${N}      Reiniciar servicio"
    echo -e " ${B}-status${N}       Estado del servicio"
    echo -e " ${B}-monitor${N}      Ver clientes activos"
    echo -e " ${B}-config${N}       Configuración rápida"
    echo ""
}

# -----------------------------------------------------
verificar_instalacion() {
    echo -e "${Y}Verificando DHCP...${N}"
    if apk info | grep -q dhcp; then
        echo -e "${G}DHCP está instalado${N}"
    else
        echo -e "${R}DHCP NO está instalado${N}"
    fi
}

# -----------------------------------------------------
instalar_dhcp() {
    echo -e "${Y}Instalando DHCP...${N}"
    apk update
    apk add dhcp
    echo -e "${G}Instalación finalizada${N}"
}

# -----------------------------------------------------
iniciar_servicio() {
    rc-service dhcpd start
    rc-update add dhcpd
}

reiniciar_servicio() {
    rc-service dhcpd restart
}

estado_servicio() {
    rc-service dhcpd status
}

# -----------------------------------------------------
monitorear_clientes() {

    if [ ! -f "$LEASES" ]; then
        echo -e "${R}No existe archivo de leases${N}"
        return
    fi

    echo -e "${B}Clientes activos:${N}"
    awk '
    /^lease/ {ip=$2; active=0}
    /hardware ethernet/ {mac=$3; gsub(";","",mac)}
    /client-hostname/ {host=$2; gsub(/[";]/,"",host)}
    /binding state active/ {active=1}
    /ends/ {
        if (active) {
            printf "%-15s %-20s %-15s\n", ip, mac, host
        }
    }
    ' "$LEASES"
}

# -----------------------------------------------------
configuracion_basica() {

    echo -e "${B}Configuración básica DHCP${N}"

    read -p "Red (ej 192.168.1.0): " red
    read -p "Mascara (ej 255.255.255.0): " mascara
    read -p "IP inicio: " ip_ini
    read -p "IP fin: " ip_fin
    read -p "Gateway: " gateway
    read -p "DNS: " dns
    read -p "Interfaz (ej eth0): " iface

    echo -e "${Y}Creando archivo configuración...${N}"

    cat > "$CONFIG" <<EOF
authoritative;

default-lease-time 600;
max-lease-time 7200;

subnet $red netmask $mascara {
    range $ip_ini $ip_fin;
    option routers $gateway;
    option domain-name-servers $dns;
    option broadcast-address ${red%0}255;
}
EOF

    echo "DHCPD_IFACE=\"$iface\"" > /etc/conf.d/dhcpd

    echo -e "${G}Configuración creada correctamente${N}"

    reiniciar_servicio
}

# -----------------------------------------------------
# MAIN
# -----------------------------------------------------

case "$1" in
    -check) verificar_instalacion ;;
    -install) instalar_dhcp ;;
    -start) iniciar_servicio ;;
    -restart) reiniciar_servicio ;;
    -status) estado_servicio ;;
    -monitor) monitorear_clientes ;;
    -config) configuracion_basica ;;
    *) mostrar_ayuda ;;
esac
