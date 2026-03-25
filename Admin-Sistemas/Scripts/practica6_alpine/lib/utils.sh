#!/bin/sh
# =============================================================================
# utilidades.sh — Funciones utilitarias
# =============================================================================

# =============================================================================
# COLORES
# =============================================================================
C_RESET='\033[0m'
C_WHITE='\033[1;37m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_BOLD='\033[1m'
C_PINK='\033[38;5;213m'

# =============================================================================
# MENSAJES
# =============================================================================
print_warning() { printf "${C_YELLOW}[WARN]  %s${C_RESET}\n" "$1"; }
print_success() { printf "${C_BLUE}[OK]    %s${C_RESET}\n" "$1"; }
print_info()    { printf "${C_WHITE}[INFO]  %s${C_RESET}\n" "$1"; }

print_menu() {
    printf "${C_PINK}%s${C_RESET}\n" "$1"
}

print_title() {
    printf "\n${C_BOLD}${C_BLUE}========================================${C_RESET}\n"
    printf "${C_BOLD}${C_BLUE}  %s${C_RESET}\n" "$1"
    printf "${C_BOLD}${C_BLUE}========================================${C_RESET}\n\n"
}

# =============================================================================
# VALIDACIONES
# =============================================================================

verificar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_warning "Ejecuta como root (sudo)"
        exit 1
    fi
}

requiere_comando() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_warning "No se encontro comando: $1"
        return 1
    fi
    return 0
}

validar_input() {
    val="$1"
    campo="$2"

    if [ -z "$val" ]; then
        print_warning "Campo '$campo' vacio"
        return 1
    fi

    if echo "$val" | grep -qE '[;|&$<>(){}\\`!]'; then
        print_warning "Caracteres no permitidos en '$campo'"
        return 1
    fi

    return 0
}

# =============================================================================
# VALIDAR PUERTO
# =============================================================================

validar_puerto() {
    p="$1"

    if ! echo "$p" | grep -qE '^[0-9]+$'; then
        print_warning "Puerto invalido"
        return 1
    fi

    if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
        print_warning "Puerto fuera de rango (1-65535)"
        return 1
    fi

    if [ "$p" -lt 1024 ] && [ "$p" -ne 80 ] && [ "$p" -ne 443 ]; then
        printf "${C_YELLOW}[WARN]  Puerto bajo (<1024)${C_RESET}\n"
    fi

    case "$p" in
        20|21|22|2122|23|25|53|110|143|3306|5432|6379|27017|40000|40001|40002|40003|40004|40005)
            print_warning "Puerto reservado"
            return 1
            ;;
    esac

    if netstat -tuln 2>/dev/null | grep -q ":$p " || \
       ss -tuln 2>/dev/null | grep -q ":$p "; then
        print_warning "Puerto en uso"
        return 1
    fi

    print_success "Puerto disponible: $p"
    return 0
}

# =============================================================================
# PEDIR PUERTO
# =============================================================================

pedir_puerto() {
    i=0
    max=3

    while [ "$i" -lt "$max" ]; do
        printf "${C_YELLOW}Ingresa puerto (ej. 8080): ${C_RESET}"
        read p_in

        if validar_input "$p_in" "puerto" && validar_puerto "$p_in"; then
            PUERTO_ELEGIDO="$p_in"
            export PUERTO_ELEGIDO
            return 0
        fi

        i=$((i+1))
        print_info "Intento $i de $max"
    done

    print_warning "Demasiados intentos"
    return 1
}

# =============================================================================
# FIREWALL
# =============================================================================

abrir_puerto_firewall() {
    p="$1"

    print_info "Configurando firewall en puerto $p..."

    if ! requiere_comando "iptables"; then
        apk add --no-cache iptables ip6tables >/dev/null 2>&1
    fi

    if ! iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$p" -j ACCEPT
        print_success "Puerto $p abierto"
    else
        print_info "Puerto ya estaba permitido"
    fi

    if command -v rc-service >/dev/null 2>&1; then
        rc-service iptables save 2>/dev/null
        print_success "Reglas guardadas"
    fi
}

# =============================================================================
# USUARIO SERVICIO
# =============================================================================

crear_usuario_servicio() {
    user="$1"
    dir="$2"

    if id "$user" >/dev/null 2>&1; then
        print_info "Usuario '$user' ya existe"
    else
        print_info "Creando usuario '$user'..."
        adduser -D -H -s /sbin/nologin "$user" >/dev/null 2>&1
        print_success "Usuario creado"
    fi

    if [ -d "$dir" ]; then
        chown -R "$user:$user" "$dir"
        chmod 750 "$dir"
        print_success "Permisos aplicados en $dir"
    fi
}

# =============================================================================
# INDEX HTML
# =============================================================================

crear_index() {
    srv="$1"
    ver="$2"
    port="$3"
    path="$4"

    mkdir -p "$path"

    cat > "$path/index.html" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Servidor Web</title>
</head>
<body style="background:#0d1117;color:#fff;font-family:sans-serif;text-align:center;padding:40px;">
<h1>$srv</h1>
<p>Version: $ver</p>
<p>Puerto: $port</p>
<p>Alpine Linux</p>
</body>
</html>
EOF

    print_success "index.html generado en $path"
}

# =============================================================================
# PAUSA
# =============================================================================

pausar() {
    printf "\n${C_YELLOW}Presiona Enter para continuar...${C_RESET}"
    read _
}