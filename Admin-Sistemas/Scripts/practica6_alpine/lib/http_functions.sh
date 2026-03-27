#!/bin/sh
# =============================================================================
# http_functions.sh — Funciones HTTP (Refactor visual)
# =============================================================================

# Validación de dependencias
[ -z "$C_RESET" ] && {
    echo "ERROR: Carga utilidades.sh primero"
    exit 1
}

# =============================================================================
# COLORES
# =============================================================================
C_WHITE='\033[1;37m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_RESET='\033[0m'

# =============================================================================
# UTILIDADES INTERNAS
# =============================================================================

_obtener_ip() {
    ip addr show | awk '/inet / && !/127.0.0.1/ {print $2}' | cut -d/ -f1 | head -1
}

_confirmar_instalacion() {
    servicio="$1"
    version="$2"
    puerto="$3"

    printf "\n${C_YELLOW}¿Instalar %s v%s en puerto %s? [s/N]: ${C_RESET}" "$servicio" "$version" "$puerto"
    read r
    echo "$r" | grep -qi '^s$'
}

# =============================================================================
# APACHE
# =============================================================================

consultar_versiones_apache() {
    print_info "Buscando versión de Apache..."
    apk update >/dev/null 2>&1

    version=$(apk info apache2 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$version" ] && version=$(apk search -x apache2 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    [ -z "$version" ] && {
        print_warning "No se pudo obtener versión"
        return 1
    }

    printf "${C_BLUE}[OK] %s${C_RESET}\n" "$version"
    echo "$version"
}

setup_apache() {
    print_title "APACHE2"

    VERSION=$(consultar_versiones_apache) || return 1
    pedir_puerto || return 1

    _confirmar_instalacion "Apache2" "$VERSION" "$PUERTO_ELEGIDO" || {
        print_info "Cancelado"
        return 0
    }

    print_info "Instalando..."
    apk add --no-cache apache2 apache2-utils >/dev/null 2>&1 || return 1

    crear_usuario_servicio "httpd-user" "/var/www/localhost/htdocs"
    adduser httpd-user apache 2>/dev/null

    configurar_puerto_apache "$PUERTO_ELEGIDO"
    configurar_seguridad_apache

    crear_index "Apache2" "$VERSION" "$PUERTO_ELEGIDO" "/var/www/localhost/htdocs"

    chown -R httpd-user:apache /var/www/localhost/htdocs
    chmod -R 755 /var/www/localhost/htdocs

    abrir_puerto_firewall "$PUERTO_ELEGIDO"

    rc-update add apache2 default >/dev/null
    rc-service apache2 restart

    verificar_servicio "apache2" "$PUERTO_ELEGIDO"

    IP=$(_obtener_ip)

    print_title "APACHE LISTO"
    print_success "http://$IP:$PUERTO_ELEGIDO"
}

configurar_puerto_apache() {
    sed -i "s/^Listen .*/Listen $1/" /etc/apache2/httpd.conf
    print_success "Puerto Apache → $1"
}

configurar_seguridad_apache() {
    conf="/etc/apache2/httpd.conf"

    grep -q "ServerTokens" "$conf" || cat >> "$conf" <<EOF
ServerTokens Prod
ServerSignature Off
TraceEnable Off
EOF

    grep -q "X-Frame-Options" "$conf" || cat >> "$conf" <<EOF
<IfModule mod_headers.c>
 Header always set X-Frame-Options "SAMEORIGIN"
 Header always set X-Content-Type-Options "nosniff"
 Header always set X-XSS-Protection "1; mode=block"
</IfModule>
EOF

    print_success "Hardening aplicado"
}

# =============================================================================
# NGINX
# =============================================================================

consultar_versiones_nginx() {
    apk update >/dev/null 2>&1
    version=$(apk info nginx 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    [ -z "$version" ] && return 1

    echo "$version"
}

setup_nginx() {
    print_title "NGINX"

    VERSION=$(consultar_versiones_nginx) || return 1
    pedir_puerto || return 1

    _confirmar_instalacion "Nginx" "$VERSION" "$PUERTO_ELEGIDO" || return 0

    apk add --no-cache nginx >/dev/null 2>&1 || return 1

    mkdir -p /var/www/html /run/nginx

    configurar_puerto_nginx "$PUERTO_ELEGIDO"
    configurar_seguridad_nginx

    crear_index "Nginx" "$VERSION" "$PUERTO_ELEGIDO" "/var/www/html"

    chown -R nginx:nginx /var/www
    chmod -R 755 /var/www/html

    rc-update add nginx default >/dev/null
    rc-service nginx restart

    verificar_servicio "nginx" "$PUERTO_ELEGIDO"

    IP=$(_obtener_ip)
    print_success "http://$IP:$PUERTO_ELEGIDO"
}

configurar_puerto_nginx() {
    cat > /etc/nginx/http.d/default.conf <<EOF
server {
    listen $1;
    root /var/www/html;
    index index.html;
}
EOF
}

configurar_seguridad_nginx() {
    sed -i '/http {/a \    server_tokens off;' /etc/nginx/nginx.conf
}

# =============================================================================
# TOMCAT (solo cambios visuales, lógica intacta)
# =============================================================================

setup_tomcat() {
    print_title "TOMCAT"

    printf "${C_WHITE}[1] 10.1.20\n[2] 10.1.34\n[3] 9.0.96${C_RESET}\n"
    read opt

    case $opt in
        1) VER="10.1.20" ;;
        2) VER="10.1.34" ;;
        3) VER="9.0.96" ;;
        *) return 1 ;;
    esac

    pedir_puerto || return 1
    _confirmar_instalacion "Tomcat" "$VER" "$PUERTO_ELEGIDO" || return 0

    print_info "Limpiando..."
    rc-service tomcat stop 2>/dev/null
    pkill -9 -f catalina 2>/dev/null

    apk add openjdk17 wget >/dev/null 2>&1

    adduser -D -h /opt/tomcat -s /sbin/nologin tomcat 2>/dev/null

    print_info "Descargando..."
    cd /tmp || return 1

    wget -q "https://dlcdn.apache.org/tomcat/tomcat-10/v${VER}/bin/apache-tomcat-${VER}.tar.gz" -O t.tar.gz || return 1

    rm -rf /opt/tomcat
    mkdir /opt/tomcat
    tar -xzf t.tar.gz -C /opt/tomcat --strip-components=1

    chown -R tomcat:tomcat /opt/tomcat

    configurar_puerto_tomcat "$PUERTO_ELEGIDO"

    rc-service tomcat start

    verificar_servicio "tomcat" "$PUERTO_ELEGIDO"

    IP=$(_obtener_ip)
    print_success "http://$IP:$PUERTO_ELEGIDO"
}

# =============================================================================
# VERIFICACIÓN
# =============================================================================

verificar_HTTP() {
    print_title "ESTADO"

    rc-service apache2 status >/dev/null && echo "Apache OK"
    rc-service nginx status >/dev/null && echo "Nginx OK"
    rc-service tomcat status >/dev/null && echo "Tomcat OK"

    echo ""
    ss -tuln | grep LISTEN
}

# =============================================================================
# VERIFICAR SERVICIO (espera que el puerto esté escuchando)
# =============================================================================

verificar_servicio() {
    servicio="$1"
    puerto="$2"
    max=6
    i=0

    print_info "Esperando que $servicio levante en :$puerto ..."

    while [ "$i" -lt "$max" ]; do
        if ss -tuln 2>/dev/null | grep -q ":$puerto "; then
            print_success "$servicio escuchando en :$puerto"
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done

    print_warning "$servicio no respondió en puerto $puerto tras $max intentos"
    return 1
}

# =============================================================================
# CONFIGURAR PUERTO TOMCAT
# =============================================================================

configurar_puerto_tomcat() {
    xml="/opt/tomcat/conf/server.xml"

    if [ ! -f "$xml" ]; then
        print_warning "No se encontró server.xml en $xml"
        return 1
    fi

    sed -i "s/port=\"8080\"/port=\"$1\"/" "$xml"
    print_success "Puerto Tomcat → $1"
}

# =============================================================================
# REVISAR RESPUESTA HTTP (curl)
# =============================================================================

revisar_HTTP() {
    print_title "RESPUESTA HTTP"

    if ! requiere_comando "curl"; then
        print_info "Instalando curl..."
        apk add --no-cache curl >/dev/null 2>&1
    fi

    IP=$(_obtener_ip)

    # Detecta puertos en escucha y prueba solo los que responden HTTP
    puertos=$(ss -tuln 2>/dev/null \
        | awk '/LISTEN/ { n=split($5,a,":"); print a[n] }' \
        | grep -E '^[0-9]+$' \
        | sort -un)

    if [ -z "$puertos" ]; then
        print_warning "No se detectaron puertos en escucha"
        return 1
    fi

    encontrado=0

    for p in $puertos; do
        # Omite puertos que claramente no son HTTP (ssh, etc.)
        case "$p" in
            22|2122) continue ;;
        esac

        result=$(curl -sk --max-time 3 -o /dev/null \
            -w "%{http_code} | %{time_total}s | %{size_download}B" \
            "http://$IP:$p" 2>/dev/null)

        code=$(echo "$result" | cut -d'|' -f1 | tr -d ' ')

        # Solo muestra si hay respuesta HTTP real (código numérico)
        if echo "$code" | grep -qE '^[0-9]{3}$'; then
            printf "${C_BLUE}[OK]    http://$IP:%-6s  → HTTP %s  (%s)${C_RESET}\n" \
                "$p" "$code" "$result"
            encontrado=$((encontrado + 1))
        fi
    done

    [ "$encontrado" -eq 0 ] && print_warning "Ningún puerto respondió HTTP"
}