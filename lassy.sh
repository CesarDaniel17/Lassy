#!/bin/bash

# =======================
# 🎨 COLORES
# =======================
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
MAGENTA="\e[35m"
RESET="\e[0m"

# =======================
# 🖼️ BANNER
# =======================
banner() {
    clear
    echo -e "${MAGENTA}"
    echo "=============================================="
    echo "        🚀 Lassy - Flow Wifi (Auditoría)       "
    echo "=============================================="
    echo -e "${RESET}"
}
banner

echo -e "${CYAN}Detectando interfaces disponibles...${RESET}"
sleep 1

# =======================
# 🔍 LISTAR INTERFACES
# =======================
interfaces=$(ls /sys/class/net)

echo -e "${YELLOW}Interfaces detectadas:${RESET}"
echo "$interfaces"
echo ""

read -p "$(echo -e ${CYAN}Selecciona la interfaz que quieres usar:${RESET} ) " iface

echo -e "${CYAN}Validando interfaz seleccionada...${RESET}"
sleep 1

# =======================
# ❗ VALIDACIÓN EXISTENCIA
# =======================
if [ ! -d "/sys/class/net/$iface" ]; then
    echo -e "${RED}La interfaz '$iface' no existe en tu sistema.${RESET}"
    exit 1
fi

# =======================
# ⚡ VALIDAR SI ESTÁ ACTIVA
# =======================
state=$(cat /sys/class/net/$iface/operstate)

if [ "$state" != "up" ]; then
    echo -e "${RED}La interfaz '$iface' no está activa.${RESET}"
    echo -e "${YELLOW}👉 Conéctala, habilítala o revisa el USB.${RESET}"
    exit 1
fi

echo -e "${GREEN}Interfaz OK y activa:${RESET} ${YELLOW}$iface${RESET}"
sleep 1

# =======================
# ❓ CONFIRMAR ACCIÓN
# =======================
read -p "$(echo -e ${MAGENTA}¿Quieres activar modo monitor? (s/n): ${RESET}) " confirm

if [[ "$confirm" != "s" ]]; then
    echo -e "${RED}Operación cancelada.${RESET}"
    exit 0
fi

# =======================
# 🎯 ACTIVAR MODO MONITOR
# =======================
echo -e "${CYAN}Activando modo monitor...${RESET}"
sleep 1

sudo airmon-ng check kill > /dev/null 2>&1

sudo airmon-ng start "$iface"

# Detectar nombre real de la nueva interfaz (p.ej. wlan0mon)
monitor_iface=$(iw dev | awk '/Interface/ {print $2}' | grep -E "mon$")

if [ -z "$monitor_iface" ]; then
    echo -e "${RED}No pude detectar automáticamente la interfaz en monitor mode.${RESET}"
    echo -e "${YELLOW}Probablemente es ${iface}mon, pero revísalo.${RESET}"
    exit 1
fi

echo -e "${GREEN}Modo monitor ACTIVADO en:${RESET} ${YELLOW}$monitor_iface${RESET}"
sleep 1

# =======================
# 📡 ESCANEO
# =======================
echo -e "${CYAN}Iniciando escaneo con Airodump-ng...${RESET}"
sleep 1
echo -e "${YELLOW}Presiona CTRL + C cuando quieras terminar.${RESET}"
sleep 1

sudo airodump-ng "$monitor_iface"

# =======================
# 🏁 FIN
# =======================
echo -e "${GREEN}Escaneo finalizado.${RESET}"
echo -e "${CYAN}Si quieres desactivar modo monitor, usa:${RESET}"
echo -e "${MAGENTA}sudo airmon-ng stop $monitor_iface${RESET}"
echo ""