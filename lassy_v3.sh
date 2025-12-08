#!/bin/bash

#Colores
RED="\e[31m"
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
MAGENTA="\e[35m"
RESET="\e[0m"

#banner
banner() {
    clear
    echo -e "${MAGENTA}"
    echo "=============================================="
    echo ""
    echo "               INICIANDO LASSY                "
    echo ""
    echo "=============================================="
    echo -e "${RESET}\n"

sudo

#interfaces WLAN
echo -e "${CYAN}Detectando interfaces disponibles..."
sleep 5

mapfile -t interfaces < <(iw dev | awk '$1=="Interface"{print $2}')

if [ ${#interfaces[@]} -eq 0 ]; then
  echo -e "${RED}No encontré interfaces Wi-Fi. Prueba la conección.${RESET}"
  exit 1
fi

if [ ${#interfaces[@]} -eq 1 ]; then
  iface="${interfaces[0]}"
  echo -e "${GREEN}Interfaz detectada automáticamente:${RESET} ${YELLOW}$iface${RESET}"
fi

# Activar monitor mode automáticamente (sin pedir más)
echo -e "${CYAN}Matando procesos conflictivos y activando monitor mode...${RESET}"
sudo airmon-ng check kill >/dev/null 2>&1
sleep 0.6
sudo airmon-ng start "$iface"
sleep 1

# Detectar la interfaz en modo monitor (buscamos interfaces con type monitor)
monitor_iface=$(iw dev | awk '
  /Interface/ { iface=$2 }
  /type/ && $2=="monitor" { print iface }' | tail -n1)

# Fallback: si no obtuvo, probar sufijo "mon"
if [ -z "$monitor_iface" ]; then
  if ip link show "${iface}mon" >/dev/null 2>&1; then
    monitor_iface="${iface}mon"
  fi
fi

if [ -z "$monitor_iface" ]; then
  echo -e "${RED}No pude detectar la interfaz en monitor mode. Revisa manualmente.${RESET}"; exit 1
fi

echo -e "${GREEN}Monitor mode activo en:${RESET} ${YELLOW}$monitor_iface${RESET}"
sleep 0.6

echo ""

# Iniciar escaneo en primer plano (mostrable), pero en background para control
echo -e "${CYAN}Iniciando escaneo en tiempo real (airodump-ng). Espera y observa...${RESET}"
# Guardamos logs temporales
tmpdir=$(mktemp -d)
airodump_log="$tmpdir/airodump.csv"

# Ejecutamos airodump-ng con salida CSV (para parseo)
sudo timeout --preserve-status 99999 airodump-ng --write-interval 1 --output-format csv -w "$tmpdir/airodump" "$monitor_iface" >/dev/null 2>&1 &
AIRO_PID=$!


# Función para listar redes leyendo CSV
list_networks(){
  csv="$tmpdir/airodump-01.csv"
  if [ ! -f "$csv" ]; then
    echo -e "${YELLOW}Esperando datos de escaneo...${RESET}"
    return 1
  fi
  # Extraer líneas de AP (antes de la línea vacía que separa APs de clientes)
  awk 'BEGIN{FS=","; OFS=","} NR>1{
    if($1!~/^Station/ && NF>6){
      bssid=$1; channel=$4; pwr=$9; enc=$6; essid=$14
      gsub(/^[ \t]+|[ \t]+$/,"",essid)
      if(length(bssid)>0) print bssid,channel,pwr,enc,essid
    }
  }' "$csv" | sort -u -k5,5
}

# Mostrar redes en tiempo real hasta que el usuario elija
while true; do
  sleep 1
  echo -e "${MAGENTA}----- Redes detectadas (actualizado) -----${RESET}"
  list_networks || true
  echo ""
  read -t 1 -p "$(echo -e ${CYAN}Pulsa ENTER para refrescar, o escribe BSSID para seleccionar una red: ${RESET})" sel
  if [ -n "$sel" ]; then
    bssid_input="$sel"
    break
  fi
done

# Validar BSSID escogido
if [ -z "$bssid_input" ]; then
  echo -e "${RED}No seleccionaste ninguna BSSID. Abortando.${RESET}"
  kill $AIRO_PID 2>/dev/null || true
  exit 1
fi

# Extraer info del CSV para ese BSSID
csv="$tmpdir/airodump-01.csv"
if [ ! -f "$csv" ]; then echo -e "${RED}No hay datos de airodump. Abortando.${RESET}"; kill $AIRO_PID 2>/dev/null || true; exit 1; fi

# Buscar la linea que contiene el BSSID
line=$(awk -F, -v b="$bssid_input" '$1 ~ b {print $0}' "$csv" | head -n1)
if [ -z "$line" ]; then
  echo -e "${YELLOW}No encontré el BSSID en los resultados actuales. Igual continuarás intentando captura pasiva.${RESET}"
  # Si no está, pedimos canal manualmente
  read -p "$(echo -e ${CYAN}Introduce el canal de la red (número): ${RESET})" channel
else
  # Campos: BSSID, First time seen, Last time seen, channel, speed, privacy, cipher, auth, power, # beacons, # IV, LAN IP, ID-length, ESSID, Key
  channel=$(echo "$line" | awk -F, '{gsub(/^[ \t]+|[ \t]+$/,"",$4); print $4}')
  channel=$(echo -n "$channel")
  echo -e "${GREEN}Red seleccionada:${RESET} ${YELLOW}$bssid_input${RESET} ${CYAN}(canal $channel)${RESET}"
fi

# Parar airodump original
echo -e "${CYAN}Deteniendo escaneo general...${RESET}"
kill $AIRO_PID 2>/dev/null || true
sleep 1

# Crear carpeta en Escritorio Lassy-<num>
DESKTOP_DIR="$HOME/Escritorio"
if [ ! -d "$DESKTOP_DIR" ]; then DESKTOP_DIR="$HOME/Desktop"; fi

read -p "$(echo -e ${CYAN}Escribe el número identificador para la carpeta (ej: 90): ${RESET})" idnum
if ! [[ "$idnum" =~ ^[0-9]+$ ]]; then echo -e "${RED}Número inválido.${RESET}"; exit 1; fi

PROJECT_DIR="$DESKTOP_DIR/Lassy-$idnum"
mkdir -p "$PROJECT_DIR"
echo -e "${GREEN}Carpeta creada:${RESET} ${YELLOW}$PROJECT_DIR${RESET}"

# Sitúate en la carpeta
cd "$PROJECT_DIR" || exit 1

# Lanzar airodump específico para capturar handshake (salida handshake-01.cap)
echo -e "${CYAN}Iniciando captura dirigida (airodump-ng) en canal ${channel} para BSSID ${bssid_input}...${RESET}"
sudo airodump-ng -c "$channel" --bssid "$bssid_input" -w handshake 