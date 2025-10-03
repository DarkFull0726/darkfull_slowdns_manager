#!/bin/bash
# DarkFull SlowDNS Manager + User Manager
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

SLOWDNS_DIR="/etc/slowdns"
SERVER_SERVICE="server-sldns"
CLIENT_SERVICE="client-sldns"
PUBKEY_FILE="$SLOWDNS_DIR/server.pub"
SCRIPT_PATH="/root/darkfull_slowdns_manager.sh"

# Zona horaria Honduras
TZ="America/Tegucigalpa"

# ---------------- FUNCIONES ----------------
menu(){
clear
echo -e "${ORANGE}---------------------------------------------${NC}"
echo -e "${ORANGE}     DarkFull SlowDNS Manager + UserMgr${NC}"
echo -e "${ORANGE}---------------------------------------------${NC}"
echo -e "Fecha/Hora Honduras: $(TZ=$TZ date)"
echo -e "${ORANGE}---------------------------------------------${NC}"
echo -e "1) Instalar SlowDNS"
echo -e "2) Ver estado SlowDNS"
echo -e "3) Iniciar SlowDNS"
echo -e "4) Detener SlowDNS"
echo -e "5) Ver Public Key"
echo -e "6) Desinstalar SlowDNS"
echo -e "---------------------------------------------"
echo -e "7) Crear usuario SSH"
echo -e "8) Ver usuarios SSH"
echo -e "9) Borrar usuario SSH"
echo -e "0) Salir"
read -rp "Selecciona una opción [0-9]: " opt
case $opt in
  1) install_slowdns ;;
  2) status_slowdns ;;
  3) start_slowdns ;;
  4) stop_slowdns ;;
  5) view_pubkey ;;
  6) uninstall_slowdns ;;
  7) create_user ;;
  8) list_users ;;
  9) delete_user ;;
  0) exit 0 ;;
  *) echo "Opción inválida"; sleep 2; menu ;;
esac
}

install_slowdns(){
echo -e "${ORANGE}[+] Instalando dependencias...${NC}"
apt update -y
apt install -y git screen iptables net-tools curl wget dos2unix sudo gnutls-bin netfilter-persistent
mkdir -p $SLOWDNS_DIR
chmod 700 $SLOWDNS_DIR

read -rp "Ingresa tu dominio NS: " DOMAIN
read -rp "Puerto de redirección SSH (por defecto 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

echo -e "${ORANGE}[+] Descargando binarios SlowDNS...${NC}"
wget -q -O $SLOWDNS_DIR/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
wget -q -O $SLOWDNS_DIR/sldns-client "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-client"
wget -q -O $SLOWDNS_DIR/server.key "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.key"
wget -q -O $SLOWDNS_DIR/server.pub "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.pub"

chmod +x $SLOWDNS_DIR/*

iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
netfilter-persistent save
netfilter-persistent reload

# Crear servicios systemd
cat > /etc/systemd/system/$CLIENT_SERVICE.service <<EOF
[Unit]
Description=Client SlowDNS
After=network.target
[Service]
Type=simple
ExecStart=$SLOWDNS_DIR/sldns-client -udp 8.8.8.8:53 --pubkey-file $PUBKEY_FILE $DOMAIN 127.0.0.1:$SSH_PORT
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/$SERVER_SERVICE.service <<EOF
[Unit]
Description=Server SlowDNS
After=network.target
[Service]
Type=simple
ExecStart=$SLOWDNS_DIR/sldns-server -udp :5300 -privkey-file $SLOWDNS_DIR/server.key $DOMAIN 127.0.0.1:$SSH_PORT
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $CLIENT_SERVICE $SERVER_SERVICE
systemctl start $CLIENT_SERVICE $SERVER_SERVICE

# Crear alias permanente
if ! grep -q "dkfslowdns" ~/.bashrc; then
    echo "alias dkfslowdns='$SCRIPT_PATH'" >> ~/.bashrc
    source ~/.bashrc
fi

echo -e "${GREEN}[✓] Instalación completada.${NC}"
echo "NS: $DOMAIN"
echo "Public Key guardada en $PUBKEY_FILE"
echo "Ahora puedes ejecutar el script con el comando: dkfslowdns"
read -rp "Presiona Enter para volver al menú..." 
menu
}

status_slowdns(){
SERVER_STATUS=$(systemctl is-active $SERVER_SERVICE)
if [ "$SERVER_STATUS" = "active" ]; then
  echo -e "${GREEN}[✓] SlowDNS Activo${NC}"
else
  echo -e "${RED}[-] SlowDNS Inactivo${NC}"
fi
if [ -f "$PUBKEY_FILE" ]; then
  echo "Public Key: $(cat $PUBKEY_FILE)"
fi
read -rp "Presiona Enter para volver al menú..." 
menu
}

start_slowdns(){
systemctl start $CLIENT_SERVICE $SERVER_SERVICE
echo -e "${GREEN}[✓] SlowDNS iniciado.${NC}"
read -rp "Presiona Enter para volver al menú..." 
menu
}

stop_slowdns(){
systemctl stop $CLIENT_SERVICE $SERVER_SERVICE
echo -e "${RED}[-] SlowDNS detenido.${NC}"
read -rp "Presiona Enter para volver al menú..." 
menu
}

view_pubkey(){
if [ -f "$PUBKEY_FILE" ]; then
  echo "Public Key: $(cat $PUBKEY_FILE)"
else
  echo "No se encontró la Public Key."
fi
read -rp "Presiona Enter para volver al menú..." 
menu
}

uninstall_slowdns(){
systemctl stop $CLIENT_SERVICE $SERVER_SERVICE
systemctl disable $CLIENT_SERVICE $SERVER_SERVICE
rm -rf $SLOWDNS_DIR
rm -f /etc/systemd/system/$CLIENT_SERVICE.service
rm -f /etc/systemd/system/$SERVER_SERVICE.service
systemctl daemon-reload
sed -i '/dkfslowdns/d' ~/.bashrc
echo -e "${RED}[✓] SlowDNS desinstalado.${NC}"
read -rp "Presiona Enter para volver al menú..." 
menu
}

# ---------------- GESTOR DE USUARIOS SSH ----------------

create_user(){
read -rp "Usuario: " USR
read -rp "Contraseña: " PASS
read -rp "Días de validez: " DAYS
EXPIRY=$(date -d "$DAYS days" +"%Y-%m-%d")

useradd -e $EXPIRY -M -s /bin/false $USR
echo "$USR:$PASS" | chpasswd

echo -e "${GREEN}[✓] Usuario creado${NC}"
echo "Usuario: $USR"
echo "Contraseña: $PASS"
echo "Expira el: $EXPIRY (Hora Honduras: $(TZ=$TZ date))"
read -rp "Presiona Enter para volver al menú..."
menu
}

list_users(){
echo -e "${ORANGE}Usuarios SSH:${NC}"
for u in $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd); do
  exp=$(chage -l $u | grep "Account expires" | awk -F": " '{print $2}')
  echo "$u - Expira: $exp"
done
read -rp "Presiona Enter para volver al menú..."
menu
}

delete_user(){
read -rp "Usuario a borrar: " USR
deluser --remove-home $USR
echo -e "${RED}[✓] Usuario $USR eliminado${NC}"
read -rp "Presiona Enter para volver al menú..."
menu
}

# ---------------- EJECUTAR ----------------
menu
