# XelajuNetwork: guía de configuración por componente

Esta guía aplica el plan de `direccionamiento.md`. Todas las direcciones, rutas y reglas salen de ese archivo; si cambian allí, hay que cambiarlas aquí.

> **Estado:** estas configuraciones no se han ejecutado todavía. Están escritas para Debian 13, pero hay que probarlas nodo por nodo en el orden de la sección 2. Los puntos con más riesgo están marcados con **Verificar**.
>
> El enunciado exige que cada integrante pueda explicar su parte. Cada sección dice qué hace cada bloque para que sirva de base a esa explicación.

## 1. Entorno de ejecución

No se usa GNS3. Cada nodo es una máquina virtual QEMU/KVM con Debian 13, o un equipo físico con Debian instalado en modo texto como sistema principal. Las VM se conectan entre sí con bridges Linux creados en el equipo anfitrión: cada segmento de red de la topología es un bridge, y cada interfaz de una VM es una interfaz virtual (tap) conectada a su bridge.

### 1.1 Nodos

| Nodo | Dónde se ejecuta | Modo | Interfaces | RAM sugerida |
|---|---|---|---|---|
| R-EDGE | VM QEMU Debian 13, o Debian físico | Texto | 3 | 512 MB |
| FW | VM QEMU Debian 13, o Debian físico | Texto | 3 | 1 GB (Suricata) |
| PROXY | VM QEMU Debian 13, o Debian físico | Texto | 2 | 1 GB |
| R2 | VM QEMU Debian 13, o Debian físico | Texto | 2 | 512 MB |
| SW1 | VM QEMU Debian 13 (bridge Linux con VLAN) | Texto | 8 | 256 MB |
| ZABBIX | VM QEMU Debian 13 | Texto (su interfaz web se usa desde un cliente) | 1 | 2 GB |
| VPN-SRV | VM QEMU Debian 13 | Texto | 1 | 256 MB |
| WEB01 / WEB02 | VM QEMU Debian 13 | Texto | 1 | 256 MB |
| SRV01 | VM QEMU Debian 13 | Texto | 1 | 256 MB |
| PC-ADMIN01, PC-USER01/02 | VM QEMU Debian con escritorio | Gráfico (permitido para clientes) | 1 | 2 GB |
| PC-REMOTO (cliente VPN) | VM QEMU Debian con escritorio conectada a `br-isp1` (ver 1.5) | Gráfico | 1 | 2 GB |
| PC-INVITADO (prueba de rechazo DHCP) | VM QEMU Debian con escritorio conectada a `br-p2` | Gráfico | 1 | 2 GB |
| Anfitrión | Equipo Linux que ejecuta QEMU y los bridges | — | — | — |

### 1.2 Bridges del anfitrión

| Bridge | Segmento | Interfaces conectadas |
|---|---|---|
| br-isp1 | ISP1 | R-EDGE eth0, interfaz USB del teléfono 1, PC-REMOTO |
| br-isp2 | ISP2 | R-EDGE eth1, interfaz USB del teléfono 2 |
| br-edge-fw | 10.10.0.0/30 | R-EDGE eth2, FW eth0 |
| br-fw-proxy | 10.10.0.4/30 | FW eth1, PROXY eth0 |
| br-proxy-r2 | 10.10.0.8/30 | PROXY eth1, R2 eth0 |
| br-dmz | 10.10.50.0/28 | FW eth2, VPN-SRV, WEB01, WEB02 |
| br-trunk | Troncal 802.1Q | R2 eth1, SW1 eth0 |
| br-p1 | Puerto 1 de SW1 (VLAN 10) | SW1 eth1, PC-ADMIN01 |
| br-p2 | Puerto 2 de SW1 (VLAN 20) | SW1 eth2, libre: cliente no registrado para la prueba de DHCP |
| br-p3 | Puerto 3 de SW1 (VLAN 20) | SW1 eth3, PC-USER01 |
| br-p4 | Puerto 4 de SW1 (VLAN 20) | SW1 eth4, PC-USER02 |
| br-p5 | Puerto 5 de SW1 (VLAN 30) | SW1 eth5, ZABBIX |
| br-p6 | Puerto 6 de SW1 (VLAN 40) | SW1 eth6, SRV01 |
| br-p7 | Puerto espejo de SW1 | SW1 eth7, captura con Wireshark |

Cada bridge `br-pN` equivale a un cable entre un puerto de SW1 y un equipo. Las VLAN las aplica SW1; estos bridges solo transportan tramas.

### 1.3 Red del anfitrión

Los dos ISP son dos teléfonos celulares conectados por USB al anfitrión, con el anclaje de red por USB activado. Cada teléfono aparece en el anfitrión como una interfaz de red (`usb0`, `usb1` o un nombre del tipo `enx…`).

Antes de ejecutar el script hay que anotar la red de cada teléfono, porque después el anfitrión ya no tendrá IP en ellas:

1. Conecta el primer teléfono y activa el anclaje por USB.
2. Ejecuta `ip -4 addr show` e `ip route` en el anfitrión, y anota la interfaz, la IP y máscara recibidas y el gateway (la IP del teléfono).
3. Repite con el segundo teléfono.
4. Comprueba que las dos redes sean distintas.

`/usr/local/sbin/lab-net.sh` en el anfitrión (ajusta `TEL1_IF` y `TEL2_IF` a los nombres anotados):

```bash
#!/bin/bash
# Crea los bridges del laboratorio y une cada teléfono a su bridge de ISP.
set -e
TEL1_IF=usb0           # teléfono 1 (ISP1)
TEL2_IF=usb1           # teléfono 2 (ISP2)

for br in br-isp1 br-isp2 br-edge-fw br-fw-proxy br-proxy-r2 br-dmz br-trunk \
          br-p1 br-p2 br-p3 br-p4 br-p5 br-p6 br-p7; do
  ip link add "$br" type bridge 2>/dev/null || true
  ip link set "$br" up
done

# Cada teléfono se une a su bridge sin IP en el anfitrión, de modo que
# solo R-EDGE usa esas conexiones.
unir() {   # $1 interfaz del teléfono, $2 bridge
  ip addr flush dev "$1"
  ip link set "$1" master "$2"
  ip link set "$1" up
}
unir "$TEL1_IF" br-isp1
unir "$TEL2_IF" br-isp2
```

`/etc/qemu/bridge.conf` en el anfitrión, para que QEMU pueda conectar las VM a los bridges:

```
allow all
```

Las direcciones WAN de R-EDGE dependen de cada teléfono. En esta guía aparecen como marcadores: `192.168.41.x` para ISP1 y `192.168.42.x` para ISP2. En cada enlace, R-EDGE usa una IP libre de la red del teléfono, configurada a mano, y el gateway es la IP del teléfono.

**Verificar:**

- **Redes distintas:** dos teléfonos del mismo tipo pueden entregar la misma red (por ejemplo, los iPhone suelen usar `172.20.10.0/28`). R-EDGE no debe tener sus dos WAN en la misma subred; si coinciden, usa otro modelo de teléfono.
- **Red estable:** algunos teléfonos cambian de red cada vez que se reactiva el anclaje. Tras cada reconexión, confirma que la red sigue siendo la anotada; si cambió, actualiza R-EDGE.
- **Gestor de red del anfitrión:** no debe volver a pedir IP en las interfaces de los teléfonos; si lo hace, márcalas como no gestionadas.

### 1.4 Creación y arranque de las VM

Cada VM usa un disco propio derivado de una imagen base de Debian 13 ya instalada, con consola serial habilitada:

```bash
mkdir -p /var/lib/xelaju
qemu-img create -f qcow2 -F qcow2 -b /ruta/a/debian13-base.qcow2 /var/lib/xelaju/R2.qcow2
```

`/usr/local/sbin/vm.sh` en el anfitrión:

```bash
#!/bin/bash
# Uso: vm.sh <nombre> <id> <ram_MB> <bridge>...
# La primera interfaz de la VM (eth0) se conecta al primer bridge, y así sucesivamente.
nombre=$1; id=$2; ram=$3; shift 3

red=(); i=0
for br in "$@"; do
  mac=$(printf '52:54:00:00:%02x:%02x' "$id" "$i")   # MAC única por VM e interfaz
  red+=(-netdev "bridge,id=n$i,br=$br" -device "e1000,netdev=n$i,mac=$mac")
  i=$((i + 1))
done

if [[ -n "${GUI:-}" ]]; then pantalla=(-display gtk); else pantalla=(-nographic); fi

exec qemu-system-x86_64 -enable-kvm -name "$nombre" -m "$ram" \
  -drive "file=/var/lib/xelaju/$nombre.qcow2,if=ide" \
  "${pantalla[@]}" "${red[@]}"
```

Arranque de cada nodo, como root y cada uno en su propia terminal (o en ventanas de `tmux`):

```bash
vm.sh R-EDGE    1  512  br-isp1 br-isp2 br-edge-fw
vm.sh FW        2  1024 br-edge-fw br-fw-proxy br-dmz
vm.sh PROXY     3  1024 br-fw-proxy br-proxy-r2
vm.sh R2        4  512  br-proxy-r2 br-trunk
vm.sh SW1       5  256  br-trunk br-p1 br-p2 br-p3 br-p4 br-p5 br-p6 br-p7
vm.sh ZABBIX    7  2048 br-p5
vm.sh SRV01     8  256  br-p6
vm.sh VPN-SRV   9  256  br-dmz
vm.sh WEB01     10 256  br-dmz
GUI=1 vm.sh PC-ADMIN01 11 2048 br-p1
GUI=1 vm.sh PC-USER01  12 2048 br-p3
GUI=1 vm.sh PC-USER02  13 2048 br-p4

# Clientes de prueba: se arrancan solo cuando hacen falta.
GUI=1 vm.sh PC-REMOTO   14 2048 br-isp1   # cliente VPN en el lado WAN
GUI=1 vm.sh PC-INVITADO 15 2048 br-p2     # MAC no registrada en el DHCP
```

La MAC de cada interfaz sale del `id`: PC-USER01 tiene `52:54:00:00:0c:00` y PC-USER02 `52:54:00:00:0d:00`. Son las que se registran en el DHCP restringido. Sin MAC explícita, todas las VM de QEMU arrancarían con la misma y la red fallaría.

### 1.5 Notas del entorno

- **Nombres de interfaz:** la guía usa `eth0`, `eth1`, … Si Debian las nombra `ens3` o `enp0s3`, añade `net.ifnames=0 biosdevname=0` a `GRUB_CMDLINE_LINUX` en `/etc/default/grub`, ejecuta `update-grub` y reinicia; o sustituye los nombres en cada archivo.
- **SW1 como VM Debian:** el enunciado pide configurar los switches por consola, y un bridge Linux con filtrado de VLAN lo permite.
- **Varios equipos físicos:** si un segmento une VMs de dos anfitriones, añade la interfaz Ethernet física al bridge de ese segmento en ambos (`ip link set <interfaz> master br-fw-proxy`) y conéctalos por cable.
- **Debian como sistema principal:** si un nodo es un equipo físico, necesita tantas interfaces de red como indica la tabla (adaptadores USB-Ethernet si faltan). Si ese nodo es R-EDGE, los dos teléfonos se conectan a él y son directamente sus interfaces WAN; no hacen falta `br-isp1` ni `br-isp2`, y sus nombres reales (`usb0`, `usb1`, …) van en `mwan.conf` y en `/etc/network/interfaces`.
- **Consumo de datos:** todo el tráfico del laboratorio sale por datos móviles. Instala los paquetes antes (sección 2.1) y evita descargas grandes durante las pruebas.
- **Sin IP pública (cliente VPN):** las redes móviles casi siempre usan CGNAT, así que un cliente no podrá iniciar la VPN desde Internet. Como el enlace USB solo une el teléfono con R-EDGE, el cliente "remoto" debe conectarse al lado WAN: usa la VM PC-REMOTO en `br-isp1` (sección 1.4), dale una IP de la red del teléfono 1 y usa como `Endpoint` la IP WAN de R-EDGE en esa red. Un equipo real fuera del laboratorio solo sirve si algún teléfono tiene IP pública.
- **Wireshark:** puede ejecutarse en el anfitrión capturando en `br-p7`, o en una VM cliente conectada a ese bridge.

## 2. Preparación común y orden de montaje

### 2.1 Paquetes

Los nodos no tendrán Internet hasta que toda la cadena funcione. Instala los paquetes antes de conectar la VM a sus bridges: arráncala una vez con la red de usuario de QEMU (añade `-nic user,model=e1000` al comando de QEMU y ejecuta `dhclient eth0` dentro), o instálalos en la imagen base antes de derivar los discos.

| Nodo | Paquetes |
|---|---|
| Todos | `nftables tcpdump curl` |
| R-EDGE | `conntrack zabbix-agent` |
| FW | `rsyslog suricata` |
| PROXY | `squid-openssl openssl python3` |
| R2 | `vlan isc-dhcp-server` |
| SW1 | `iproute2` (ya incluido) |
| ZABBIX | `zabbix-server-mysql zabbix-frontend-php zabbix-agent mariadb-server apache2 libapache2-mod-php php-mysql` |
| VPN-SRV | `wireguard` |
| WEB01 / WEB02 | `nginx` y `ngrok` (ver 6.3) |
| Clientes | `wireguard`, `nmap`, `wireshark`, navegador |

### 2.2 Ajustes comunes a todos los nodos de infraestructura

```bash
hostnamectl set-hostname <NOMBRE>
timedatectl set-timezone America/Guatemala   # los logs deben tener fecha y hora correctas
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

En los nodos que enrutan (R-EDGE, FW, PROXY, R2, VPN-SRV), crea `/etc/sysctl.d/99-router.conf`:

```ini
net.ipv4.ip_forward = 1
```

Y aplícalo con `sysctl --system`. La red de cada nodo se define en `/etc/network/interfaces` y se aplica con `systemctl restart networking`.

### 2.3 Orden de montaje

Monta y prueba en este orden; cada paso depende del anterior:

1. SW1, R2 y los equipos de las VLAN: ping entre VLANs sin ACL.
2. PROXY solo como router (sin Squid) y FW con `policy accept` temporal.
3. R-EDGE con un solo ISP y NAT: Internet desde una VLAN.
4. Multi-WAN completo (segundo ISP, políticas, failover).
5. ACL de R2 y DHCP restringido.
6. Squid transparente y portal.
7. DMZ, WireGuard y ngrok.
8. Reglas definitivas del firewall, logs, Suricata.
9. Zabbix y sus métricas.

## 3. Estudiante 1: LAN, VLANs, router, DHCP y Zabbix

### 3.1 SW1: VLANs, troncal y puertos de acceso

Asignación de puertos:

| Puerto | Modo | VLAN | Conectado a |
|---|---|---|---|
| eth0 | Troncal 802.1Q | 10, 20, 30, 40 | R2 eth1 |
| eth1 | Acceso | 10 | PC-ADMIN01 |
| eth2 | Acceso | 20 | Libre: cliente no registrado (prueba de DHCP) |
| eth3 | Acceso | 20 | PC-USER01 |
| eth4 | Acceso | 20 | PC-USER02 |
| eth5 | Acceso | 30 | ZABBIX |
| eth6 | Acceso | 40 | SRV01 |
| eth7 | Espejo (SPAN) | — | Equipo con Wireshark |

`/usr/local/sbin/sw1-vlans.sh`:

```bash
#!/bin/bash
# Bridge con filtrado de VLAN: se comporta como un switch 802.1Q.
set -e
ip link add br0 type bridge vlan_filtering 1
ip link set br0 up

for i in eth0 eth1 eth2 eth3 eth4 eth5 eth6; do
  ip link set "$i" master br0
  ip link set "$i" up
  bridge vlan del dev "$i" vid 1        # quita la VLAN 1 por defecto
done

# Troncal: transporta las cuatro VLAN etiquetadas.
for v in 10 20 30 40; do bridge vlan add dev eth0 vid "$v"; done

# Acceso: la trama entra sin etiqueta y se asigna a la VLAN (pvid).
acceso() { bridge vlan add dev "$1" vid "$2" pvid untagged; }
acceso eth1 10
acceso eth2 20
acceso eth3 20
acceso eth4 20
acceso eth5 30
acceso eth6 40

# SPAN: copia a eth7 todo lo que entra y sale por la troncal.
ip link set eth7 up
tc qdisc add dev eth0 clsact
tc filter add dev eth0 ingress matchall action mirred egress mirror dev eth7
tc filter add dev eth0 egress  matchall action mirred egress mirror dev eth7
```

Para que se ejecute al arrancar, crea `/etc/systemd/system/sw1-vlans.service`. Este mismo patrón de unidad sirve para los demás scripts de la guía:

```ini
[Unit]
Description=VLANs de SW1
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/sw1-vlans.sh

[Install]
WantedBy=multi-user.target
```

```bash
chmod +x /usr/local/sbin/sw1-vlans.sh
systemctl enable --now sw1-vlans.service
bridge vlan show          # comprobación
```

### 3.2 R2: subinterfaces, gateways y ruta por defecto

`/etc/network/interfaces` en R2:

```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 10.10.0.10/30
    gateway 10.10.0.9

auto eth1
iface eth1 inet manual

auto eth1.10
iface eth1.10 inet static
    address 10.10.10.1/27

auto eth1.20
iface eth1.20 inet static
    address 10.10.20.1/25

auto eth1.30
iface eth1.30 inet static
    address 10.10.30.1/28

auto eth1.40
iface eth1.40 inet static
    address 10.10.40.1/27
```

Cada subinterfaz `eth1.N` recibe las tramas etiquetadas con la VLAN N y es el gateway de esa VLAN. El enrutamiento entre VLANs ocurre porque R2 tiene las cuatro redes conectadas y `ip_forward` activo. La única ruta estática es la ruta por defecto hacia PROXY.

### 3.3 R2: ACL entre VLANs

`/etc/nftables.conf` en R2:

```
#!/usr/sbin/nft -f
flush ruleset

define ADMIN   = 10.10.10.0/27
define USERS   = 10.10.20.0/25
define MGMT    = 10.10.30.0/28
define SERVERS = 10.10.40.0/27
define ZABBIX  = 10.10.30.2

table inet acl {
  chain forward {
    type filter hook forward priority filter; policy drop;

    # Tráfico de retorno de conexiones ya permitidas.
    ct state established,related accept
    ct state invalid drop

    # USERS
    ip saddr $USERS ip daddr $ADMIN   log prefix "ACL-DENY " drop
    ip saddr $USERS ip daddr $MGMT    log prefix "ACL-DENY " drop
    ip saddr $USERS ip daddr $SERVERS tcp dport { 80, 443 } accept
    ip saddr $USERS ip daddr $SERVERS log prefix "ACL-DENY " drop

    # ADMIN
    ip saddr $ADMIN ip daddr { $SERVERS, $USERS } accept
    ip saddr $ADMIN ip daddr $ZABBIX tcp dport { 22, 80, 443 } accept
    ip saddr $ADMIN ip daddr $MGMT icmp type echo-request accept

    # SERVERS y ZABBIX (monitoreo)
    ip saddr $SERVERS ip daddr $ZABBIX tcp dport 10051 accept
    ip saddr $ZABBIX ip daddr $SERVERS tcp dport 10050 accept
    ip saddr $ZABBIX ip daddr $SERVERS udp dport 161 accept
    ip saddr $ZABBIX ip daddr $SERVERS icmp type echo-request accept
    ip saddr $SERVERS ip daddr { $ADMIN, $USERS } log prefix "ACL-DENY " drop

    # Hacia fuera de la LAN y desde fuera: lo controla el firewall perimetral.
    iifname "eth1.*" oifname "eth0" accept
    iifname "eth0" oifname "eth1.*" accept

    log prefix "ACL-DENY " drop
  }
}
```

```bash
systemctl enable --now nftables
nft list ruleset
journalctl -k | grep ACL-DENY     # evidencia de bloqueos
```

Las dos reglas de `eth0` existen porque el enunciado prohíbe duplicar funciones: R2 solo decide entre VLANs; lo que entra o sale de la LAN lo decide FW.

### 3.4 R2: DHCP restringido por MAC (VLAN 20)

El servicio DHCP corre en el propio R2 y escucha solo en la subinterfaz de la VLAN 20, así que ninguna otra VLAN recibe respuestas. No necesita red propia ni relay: usa la dirección `10.10.20.1` que R2 ya tiene en `eth1.20`. Tampoco hay que tocar las ACL, porque solo filtran el tráfico que atraviesa R2, no el que llega al propio router.

`/etc/default/isc-dhcp-server` en R2:

```
INTERFACESv4="eth1.20"
```

`/etc/dhcp/usuarios.csv` (registro de equipos autorizados; las MAC son las que asigna `vm.sh`, sección 1.4):

```
# Equipo,MAC,IP
PC-USER01,52:54:00:00:0c:00,10.10.20.10
PC-USER02,52:54:00:00:0d:00,10.10.20.11
```

`/etc/dhcp/dhcpd.conf`:

```
authoritative;
default-lease-time 3600;
max-lease-time 7200;

# Rechaza a todo equipo que no tenga una declaración "host".
deny unknown-clients;

subnet 10.10.20.0 netmask 255.255.255.128 {
  option routers 10.10.20.1;
  option subnet-mask 255.255.255.128;
  option broadcast-address 10.10.20.127;
  option domain-name-servers 8.8.8.8, 1.1.1.1;
  # Sin "range": no existe un pool dinámico del que repartir.
}

include "/etc/dhcp/reservas.conf";
```

`/usr/local/sbin/dhcp-reservas.sh` convierte el CSV en reservas y recarga el servicio:

```bash
#!/bin/bash
# Genera /etc/dhcp/reservas.conf a partir de usuarios.csv.
set -e
CSV=/etc/dhcp/usuarios.csv
OUT=/etc/dhcp/reservas.conf

: > "$OUT"
while IFS=, read -r equipo mac ip; do
  [[ -z "$equipo" || "$equipo" == \#* ]] && continue
  printf 'host %s { hardware ethernet %s; fixed-address %s; }\n' \
    "$equipo" "$mac" "$ip" >> "$OUT"
done < "$CSV"

dhcpd -t -cf /etc/dhcp/dhcpd.conf      # valida antes de reiniciar
systemctl restart isc-dhcp-server
```

```bash
chmod +x /usr/local/sbin/dhcp-reservas.sh
dhcp-reservas.sh
systemctl enable isc-dhcp-server
```

La restricción tiene dos capas: no hay `range`, así que no existe un pool, y `deny unknown-clients` descarta las solicitudes de MAC sin reserva. Para registrar un equipo nuevo se añade una línea al CSV y se ejecuta el script.

### 3.5 ZABBIX: servidor de monitoreo (VLAN 30)

`/etc/network/interfaces` en ZABBIX:

```
auto eth0
iface eth0 inet static
    address 10.10.30.2/28
    gateway 10.10.30.1
```

Instalación con los paquetes de Debian. **Verificar** las rutas de los esquemas con `dpkg -L zabbix-server-mysql`, porque cambian entre versiones del paquete:

```bash
mysql -e "CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
          CREATE USER zabbix@localhost IDENTIFIED BY 'CAMBIAR_CLAVE';
          GRANT ALL PRIVILEGES ON zabbix.* TO zabbix@localhost;"

for f in schema images data; do
  zcat /usr/share/zabbix-server-mysql/$f.sql.gz | mysql -uzabbix -p'CAMBIAR_CLAVE' zabbix
done
```

En `/etc/zabbix/zabbix_server.conf`:

```
DBName=zabbix
DBUser=zabbix
DBPassword=CAMBIAR_CLAVE
```

```bash
a2enconf zabbix-frontend-php
systemctl enable --now zabbix-server apache2
```

Restringe la interfaz web a la VLAN de Administración en la configuración de Apache del frontend (bloque `<Directory>` de Zabbix):

```apache
Require ip 10.10.10.0/27
```

Esta restricción se suma a la ACL de R2, que ya impide que USERS llegue a la VLAN 30. Después, desde PC-ADMIN01:

1. Abre `http://10.10.30.2/zabbix` y completa el asistente (usuario inicial `Admin`, clave `zabbix`; cámbiala).
2. Crea el host `R-EDGE` con interfaz de agente `10.10.0.1:10050` y la plantilla "Linux by Zabbix agent".
3. Crea un dashboard con gráficas de bits recibidos y enviados de `eth0` (ISP1) y `eth1` (ISP2).

### 3.6 Clientes de las VLAN

- **PC-ADMIN01:** estática `10.10.10.10/27`, gateway `10.10.10.1`, DNS `8.8.8.8`.
- **SRV01:** estática `10.10.40.10/27`, gateway `10.10.40.1`; instala `nginx` para probar el acceso por 80/443.
- **PC-USER01 / PC-USER02:** DHCP (`iface eth0 inet dhcp` o el gestor de red del escritorio).

### 3.7 Pruebas del estudiante 1

| Prueba | Comando | Resultado esperado |
|---|---|---|
| Troncal y VLANs | `bridge vlan show` en SW1 | Puertos con su VLAN |
| Inter-VLAN permitido | `ping 10.10.40.10` desde PC-ADMIN01 | Responde |
| ACL bloquea | `ping 10.10.10.10` desde PC-USER01 | Sin respuesta, línea `ACL-DENY` en R2 |
| Servicio permitido | `curl http://10.10.40.10` desde PC-USER01 | Responde |
| Servicio denegado | `ssh 10.10.40.10` desde PC-USER01 | Bloqueado |
| DHCP registrado | `dhclient -v eth0` en PC-USER01 | Recibe siempre 10.10.20.10 |
| DHCP no registrado | Arrancar PC-INVITADO (MAC sin registrar, puerto libre `br-p2`) y pedir IP | No recibe IP; en `journalctl -u isc-dhcp-server` de R2 hay DISCOVER sin OFFER |

## 4. Estudiante 2: proxy Squid transparente

### 4.1 Cómo funciona

PROXY está en línea entre R2 y FW, así que todo el tráfico de las VLAN lo atraviesa. Con TPROXY, el kernel desvía a Squid las conexiones web de ADMIN y USERS sin que el cliente configure nada, y Squid sale a Internet **conservando la IP del cliente como origen**. Eso último es lo que permite que el firewall y el Multi-WAN sigan aplicando reglas por IP de origen.

- **HTTP (puerto 80):** Squid lee la cabecera `Host` y aplica la lista.
- **HTTPS (puerto 443):** Squid no descifra. Lee el nombre del sitio en el SNI del saludo TLS (`peek`); si está en la lista corta la conexión (`terminate`), y si no la deja pasar intacta (`splice`).

### 4.2 Red y enrutamiento de PROXY

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 10.10.0.6/30
    gateway 10.10.0.5

auto eth1
iface eth1 inet static
    address 10.10.0.9/30
    up ip route add 10.10.10.0/27 via 10.10.0.10
    up ip route add 10.10.20.0/25 via 10.10.0.10
    up ip route add 10.10.30.0/28 via 10.10.0.10
    up ip route add 10.10.40.0/27 via 10.10.0.10
    # TPROXY: los paquetes marcados se entregan al propio equipo (a Squid).
    up ip rule add fwmark 1 lookup 100
    up ip route add local 0.0.0.0/0 dev lo table 100
```

Añade a `/etc/sysctl.d/99-router.conf`:

```ini
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.eth0.rp_filter = 0
net.ipv4.conf.eth1.rp_filter = 0
```

El filtro de ruta inversa se desactiva porque, con TPROXY, las respuestas de Internet llegan a PROXY dirigidas a la IP del cliente y el kernel las descartaría.

### 4.3 Intercepción y acceso al portal

`/etc/nftables.conf` en PROXY:

```
#!/usr/sbin/nft -f
flush ruleset

define ADMIN    = 10.10.10.0/27
define USERS    = 10.10.20.0/25
define INTERNAS = { 10.10.0.0/16, 10.200.0.0/16 }

table ip proxy {
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;

    # Paquetes de conexiones que Squid ya atiende.
    meta l4proto tcp socket transparent 1 meta mark set 1 accept

    # Web de ADMIN y USERS hacia Internet: se desvía a Squid.
    iifname "eth1" ip saddr { $ADMIN, $USERS } ip daddr != $INTERNAS tcp dport 80  tproxy to :3129 meta mark set 1 accept
    iifname "eth1" ip saddr { $ADMIN, $USERS } ip daddr != $INTERNAS tcp dport 443 tproxy to :3130 meta mark set 1 accept
  }

  chain input {
    type filter hook input priority filter; policy accept;

    # Portal de consulta: solo la VLAN de Administración.
    tcp dport 8080 ip saddr != $ADMIN log prefix "PORTAL-DENY " drop
  }
}
```

El resto del tráfico (DNS, SSH, VPN, etc.) no coincide con las reglas de desvío y se enruta normalmente hacia el firewall y el Multi-WAN, como pide el enunciado.

### 4.4 Squid

Certificado para el puerto HTTPS (solo lo exige Squid para abrir el puerto; no se usa para descifrar):

```bash
mkdir -p /etc/squid/ssl
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
  -subj "/CN=proxy.xelaju.local" \
  -keyout /etc/squid/ssl/squid.pem -out /etc/squid/ssl/squid.pem
chown -R proxy:proxy /etc/squid/ssl && chmod 600 /etc/squid/ssl/squid.pem
```

Listas de bloqueo, un dominio por línea. El punto inicial incluye los subdominios; no repitas el dominio sin punto, porque Squid lo rechaza como duplicado.

`/etc/squid/admins_blacklist`:

```
.ilovepdf.com
.facebook.com
```

`/etc/squid/users_blacklist`:

```
.facebook.com
.youtube.com
.tiktok.com
.instagram.com
```

`/etc/squid/squid.conf` (reemplaza el archivo completo):

```
# Puertos: 3128 normal (obligatorio), 3129 HTTP y 3130 HTTPS interceptados.
http_port 3128
http_port 3129 tproxy
https_port 3130 tproxy ssl-bump tls-cert=/etc/squid/ssl/squid.pem generate-host-certificates=off

# Redes de origen.
acl admin_net src 10.10.10.0/27
acl users_net src 10.10.20.0/25

# Listas en archivos independientes: HTTP (Host) y HTTPS (SNI).
acl admins_bl     dstdomain -n "/etc/squid/admins_blacklist"
acl users_bl      dstdomain -n "/etc/squid/users_blacklist"
acl admins_bl_sni ssl::server_name "/etc/squid/admins_blacklist"
acl users_bl_sni  ssl::server_name "/etc/squid/users_blacklist"

# HTTPS: leer el SNI, cortar lo bloqueado, dejar pasar el resto sin descifrar.
acl step1 at_step SslBump1
ssl_bump peek step1
ssl_bump terminate admin_net admins_bl_sni
ssl_bump terminate users_net users_bl_sni
ssl_bump splice all

# HTTP: cada red con su lista.
http_access deny !CONNECT admin_net admins_bl
http_access deny !CONNECT users_net users_bl
http_access allow admin_net
http_access allow users_net
http_access allow localhost
http_access deny all

# Registro: fecha, IP origen, resultado, método, URL, SNI, acción TLS, bytes.
logformat xelaju %{%Y-%m-%dT%H:%M:%S}tl %>a %Ss/%03>Hs %rm %ru %ssl::>sni %ssl::bump_mode %<st
access_log /var/log/squid/access.log xelaju

cache deny all
visible_hostname proxy.xelaju.local
```

```bash
squid -k parse                    # valida la configuración
systemctl enable --now nftables
systemctl restart squid
```

Para cambiar una política durante la calificación: edita el archivo de lista y ejecuta `squid -k reconfigure`. No se toca `squid.conf`.

**Verificar:** que `squid -v` muestre `--with-openssl` (lo aporta el paquete `squid-openssl`) y que `squid -k parse` acepte las opciones `tproxy` y `ssl-bump`.

### 4.5 Portal de administración y consulta

`/opt/portal/portal.py`:

```python
#!/usr/bin/env python3
"""Portal de consulta de los registros de Squid (solo lectura)."""
import html
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LOG = "/var/log/squid/access.log"
BIND = ("10.10.0.9", 8080)
MAX_ROWS = 300


def parse(line):
    p = line.split()
    if len(p) < 8:
        return None
    when, src, result, method, url, sni, mode = p[:7]
    if sni != "-":
        domain = sni
    else:
        domain = urlparse(url if "://" in url else "//" + url).hostname or url
    blocked = "DENIED" in result or mode == "terminate"
    return {"when": when, "src": src, "method": method, "domain": domain,
            "result": result, "action": "BLOQUEADO" if blocked else "PERMITIDO"}


def load(ip, dom):
    rows = []
    with open(LOG, errors="replace") as f:
        for line in f:
            r = parse(line)
            if r and (not ip or r["src"] == ip) and (not dom or dom in r["domain"]):
                rows.append(r)
    return rows


def table(headers, rows):
    head = "".join(f"<th>{html.escape(h)}</th>" for h in headers)
    body = "".join(
        "<tr>" + "".join(f"<td>{html.escape(str(c))}</td>" for c in r) + "</tr>"
        for r in rows)
    return f"<table border='1' cellpadding='4'><tr>{head}</tr>{body}</table>"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        q = parse_qs(urlparse(self.path).query)
        ip = q.get("ip", [""])[0].strip()
        dom = q.get("dominio", [""])[0].strip()
        rows = load(ip, dom)
        blocked = sum(r["action"] == "BLOQUEADO" for r in rows)
        recent = [(r["when"], r["src"], r["method"], r["domain"], r["result"], r["action"])
                  for r in reversed(rows[-MAX_ROWS:])]
        page = f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<title>Portal Squid - XelajuNetwork</title></head><body>
<h1>Registros del proxy</h1>
<form>IP origen <input name="ip" value="{html.escape(ip)}">
Dominio <input name="dominio" value="{html.escape(dom)}">
<button>Filtrar</button> <a href="/">Limpiar</a></form>
<h2>Estadísticas</h2>
<p>Solicitudes: {len(rows)} | Permitidas: {len(rows) - blocked} | Bloqueadas: {blocked}</p>
<h3>Dominios más solicitados</h3>
{table(["Dominio", "Solicitudes"], Counter(r["domain"] for r in rows).most_common(10))}
<h3>Clientes con más solicitudes</h3>
{table(["IP origen", "Solicitudes"], Counter(r["src"] for r in rows).most_common(10))}
<h2>Últimas {MAX_ROWS} solicitudes</h2>
{table(["Fecha y hora", "IP origen", "Método", "Dominio", "Resultado", "Acción"], recent)}
</body></html>"""
        body = page.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(BIND, Handler).serve_forever()
```

`/etc/systemd/system/portal-squid.service`:

```ini
[Unit]
Description=Portal de consulta de registros de Squid
After=network-online.target squid.service
Wants=network-online.target

[Service]
User=proxy
ExecStart=/usr/bin/python3 /opt/portal/portal.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now portal-squid.service
```

El portal corre como el usuario `proxy` porque es el dueño de `access.log`. Usa el log de Squid como única fuente, como exige el enunciado.

### 4.6 Pruebas del estudiante 2

| Prueba | Desde | Resultado esperado |
|---|---|---|
| Navegación permitida | PC-USER01: `curl -I https://www.debian.org` | Responde; línea `TCP_TUNNEL` con acción `splice` en el log |
| Bloqueo USERS | PC-USER01: abrir `youtube.com` | Falla; línea con acción `terminate` |
| Lista diferenciada | PC-ADMIN01: abrir `youtube.com` | Carga (no está en `admins_blacklist`) |
| Bloqueo ADMIN | PC-ADMIN01: abrir `ilovepdf.com` | Falla |
| Bloqueo HTTP | `curl -I http://<dominio bloqueado>` | `403` y `TCP_DENIED` en el log |
| Cambio en caliente | Añadir un dominio y `squid -k reconfigure` | Se bloquea sin reiniciar |
| Portal permitido | PC-ADMIN01: `http://10.10.0.9:8080` | Muestra registros |
| Portal denegado | PC-USER01: misma URL | Sin acceso; `PORTAL-DENY` en `journalctl -k` |
| Logs | `tail -f /var/log/squid/access.log` | IP, fecha, dominio, método, resultado |

## 5. Estudiante 3: Multi-WAN, balanceo y failover

### 5.1 Cómo funciona

- **Tablas de ruteo por ISP:** la tabla 101 sale por ISP1 y la 102 por ISP2.
- **Políticas:** nftables marca la primera conexión según el archivo de políticas (marca 1 = ISP1, marca 2 = ISP2) y guarda la marca en la conexión. Una regla `ip rule` envía cada marca a su tabla.
- **Balanceo:** lo que no coincide con ninguna política usa la ruta por defecto de la tabla principal, que tiene los dos gateways con peso 1 (50 % / 50 %). El kernel elige el enlace con un hash de origen, destino y puertos, así que todos los paquetes de una misma conexión salen por el mismo ISP.
- **Failover:** un servicio hace ping por cada ISP cada 5 segundos. Si uno cae, redirige su marca a la tabla del otro y deja una sola ruta por defecto; cuando vuelve, restaura todo.
- **Tráfico del proxy:** Squid usa TPROXY y conserva la IP del cliente, así que las políticas por IP de origen se aplican igual al tráfico web. Esta es la respuesta a la "Consideración sobre el tráfico del Proxy" del enunciado.

### 5.2 Red de R-EDGE

> **Antes de aplicar: direcciones WAN.**
>
> - **ISP1 (teléfono 1) e ISP2 (teléfono 2):** las dos redes dependen de lo que entregue cada teléfono por USB. Los valores `192.168.41.x` y `192.168.42.x` de abajo son marcadores; usa la red y el gateway anotados en la sección 1.3.
> - **Redes distintas:** R-EDGE no debe tener sus dos WAN en la misma subred (ver los puntos de verificación de la sección 1.3).
>
> Los valores reales deben coincidir en tres sitios: `/etc/network/interfaces` de R-EDGE, `/etc/multiwan/mwan.conf` y la tabla de `direccionamiento.md`.

`/etc/network/interfaces` (sin `gateway`: la ruta por defecto la gestiona el servicio Multi-WAN):

```
auto eth0
iface eth0 inet static
    address 192.168.41.2/24       # ISP1: MARCADOR, usar la red del teléfono 1

auto eth1
iface eth1 inet static
    address 192.168.42.2/24       # ISP2: MARCADOR, usar la red del teléfono 2

auto eth2
iface eth2 inet static
    address 10.10.0.1/30
    up ip route add 10.10.0.0/16   via 10.10.0.2
    up ip route add 10.200.10.0/24 via 10.10.0.2
    up ip route add 10.200.20.0/24 via 10.10.0.2
```

Añade a `/etc/sysctl.d/99-router.conf`:

```ini
net.ipv4.fib_multipath_hash_policy = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
```

### 5.3 Archivos de configuración

`/etc/multiwan/mwan.conf`:

```bash
ISP1_IF=eth0
ISP1_GW=192.168.41.1     # MARCADOR: gateway del teléfono 1
ISP2_IF=eth1
ISP2_GW=192.168.42.1     # MARCADOR: gateway del teléfono 2
LAN_IF=eth2
CHECK_IP=1.1.1.1
INTERVALO=5
```

`/etc/multiwan/politicas.conf` (archivo externo y modificable que pide el enunciado):

```
# <ip_origen>, <puertos>, <protocolo>, <ISP_salida>
10.10.20.10, [80,443], TCP, ISP1
10.10.20.10, [53], UDP, ISP2
10.10.20.11, [443], TCP, ISP1
10.10.10.0/27, [443], TCP, ISP1
10.10.40.0/27, [443], TCP, ISP2
10.10.10.10, [22], TCP, ISP2
```

### 5.4 Script de políticas y NAT

`/usr/local/sbin/mwan-apply.sh`:

```bash
#!/bin/bash
# Lee politicas.conf y genera las reglas de marcado, NAT y tablas de ruteo.
set -euo pipefail
. /etc/multiwan/mwan.conf
POL=/etc/multiwan/politicas.conf
NFT=/run/mwan.nft

re='^[[:space:]]*([0-9./]+)[[:space:]]*,[[:space:]]*\[([0-9,[:space:]]+)\][[:space:]]*,[[:space:]]*([A-Za-z]+)[[:space:]]*,[[:space:]]*ISP([12])[[:space:]]*$'
reglas=""
while IFS= read -r linea; do
  linea=${linea%%#*}
  if [[ $linea =~ $re ]]; then
    origen=${BASH_REMATCH[1]}
    puertos=${BASH_REMATCH[2]// /}
    proto=${BASH_REMATCH[3],,}
    isp=${BASH_REMATCH[4]}
    reglas+="    ip saddr $origen $proto dport { $puertos } meta mark set $isp log prefix \"MWAN-POL ISP$isp \" return"$'\n'
  elif [[ -n ${linea//[[:space:]]/} ]]; then
    echo "Linea ignorada: $linea" >&2
  fi
done < "$POL"

cat > "$NFT" <<EOF
table ip mwan
delete table ip mwan
table ip mwan {
  chain politicas {
$reglas  }

  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;
    # Conexión ya clasificada: se reutiliza su marca.
    ct mark != 0 meta mark set ct mark accept
    # Lo que entra por un ISP debe responderse por el mismo ISP.
    iifname "$ISP1_IF" ct mark set 1 accept
    iifname "$ISP2_IF" ct mark set 2 accept
    # Conexión nueva hacia Internet: se evalúan las políticas.
    iifname "$LAN_IF" ip daddr != { 10.10.0.0/16, 10.200.0.0/16 } jump politicas
    meta mark != 0 ct mark set meta mark
  }

  chain dstnat {
    type nat hook prerouting priority dstnat; policy accept;
    # WireGuard: se reenvía al servidor VPN de la DMZ.
    iifname { "$ISP1_IF", "$ISP2_IF" } udp dport 51820 dnat to 10.10.50.2
  }

  chain srcnat {
    type nat hook postrouting priority srcnat; policy accept;
    # NAT de salida; el log registra por qué ISP salió cada conexión.
    oifname "$ISP1_IF" log prefix "MWAN-OUT ISP1 " masquerade
    oifname "$ISP2_IF" log prefix "MWAN-OUT ISP2 " masquerade
  }
}
EOF
nft -f "$NFT"

# Tablas fijas por ISP y reglas base.
ip route replace default via "$ISP1_GW" dev "$ISP1_IF" table 101
ip route replace default via "$ISP2_GW" dev "$ISP2_IF" table 102
for p in 100 110 111; do ip rule del prio "$p" 2>/dev/null || true; done
ip rule add prio 100 to 10.0.0.0/8 lookup main        # destinos internos
ip rule add prio 110 fwmark 0x11 lookup 101           # sondeo de ISP1
ip rule add prio 111 fwmark 0x12 lookup 102           # sondeo de ISP2
echo "Politicas aplicadas."
```

Después de editar `politicas.conf` se ejecuta `mwan-apply.sh`; no hay que tocar el script ni las reglas.

### 5.5 Servicio de failover

`/usr/local/sbin/mwan-monitor.sh`:

```bash
#!/bin/bash
# Vigila los dos ISP y ajusta rutas y reglas cuando uno cae o vuelve.
. /etc/multiwan/mwan.conf

sondeo() {   # $1 interfaz, $2 marca
  ping -c 3 -W 2 -I "$1" -m "$2" "$CHECK_IP" >/dev/null 2>&1 && echo up || echo down
}

aplicar() {  # $1 estado ISP1, $2 estado ISP2
  ip rule del prio 200 2>/dev/null
  ip rule del prio 201 2>/dev/null
  case "$1$2" in
    upup)
      t1=101; t2=102
      ip route replace default \
        nexthop via "$ISP1_GW" dev "$ISP1_IF" weight 1 \
        nexthop via "$ISP2_GW" dev "$ISP2_IF" weight 1 ;;
    updown)
      t1=101; t2=101
      ip route replace default via "$ISP1_GW" dev "$ISP1_IF" ;;
    downup)
      t1=102; t2=102
      ip route replace default via "$ISP2_GW" dev "$ISP2_IF" ;;
    *)
      logger -t multiwan "ISP1=down ISP2=down: sin salida a Internet"
      return ;;
  esac
  ip rule add prio 200 fwmark 1 lookup "$t1"
  ip rule add prio 201 fwmark 2 lookup "$t2"
  conntrack -F >/dev/null 2>&1      # las conexiones se rehacen por el enlace vigente
  logger -t multiwan "ISP1=$1 ISP2=$2 -> marca1=tabla$t1 marca2=tabla$t2"
}

/usr/local/sbin/mwan-apply.sh
previo=""
while true; do
  actual="$(sondeo "$ISP1_IF" 0x11) $(sondeo "$ISP2_IF" 0x12)"
  if [[ "$actual" != "$previo" ]]; then
    aplicar $actual
    previo="$actual"
  fi
  sleep "$INTERVALO"
done
```

`/etc/systemd/system/multiwan.service`:

```ini
[Unit]
Description=Multi-WAN: politicas, balanceo y failover
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/sbin/mwan-monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
chmod +x /usr/local/sbin/mwan-*.sh
systemctl enable --now multiwan.service
```

Los sondeos usan marcas propias (0x11 y 0x12) que siempre apuntan a la tabla de su ISP. Así el servicio puede detectar que un enlace volvió aunque en ese momento no tenga tráfico.

### 5.6 Métricas hacia Zabbix

En `/etc/zabbix/zabbix_agentd.conf` de R-EDGE:

```
Server=10.10.30.2
ServerActive=10.10.30.2
Hostname=R-EDGE
```

```bash
systemctl enable --now zabbix-agent
```

El agente expone el tráfico de entrada y salida de `eth0` (ISP1) y `eth1` (ISP2); la plantilla de Zabbix los descubre sola.

### 5.7 Pruebas del estudiante 3

| Prueba | Comando en R-EDGE | Resultado esperado |
|---|---|---|
| Reglas generadas | `nft list table ip mwan` | Una regla por línea de `politicas.conf` |
| Tablas | `ip rule` y `ip route show table 101` | Marcas 1 y 2 hacia 101 y 102 |
| Política por ISP | `tcpdump -ni eth0 tcp port 443` mientras PC-USER01 navega | El tráfico sale por el ISP de la política |
| Registro | `journalctl -k \| grep MWAN` | Líneas `MWAN-POL` y `MWAN-OUT` con origen e ISP |
| Balanceo | `tcpdump` en ambos enlaces con tráfico sin política (por ejemplo, ICMP a varios destinos) | Conexiones repartidas |
| Failover | En el anfitrión: `ip link set br-isp1 down` | En unos 10 s: `journalctl -t multiwan` muestra `ISP1=down` y todo sale por ISP2 |
| Recuperación | En el anfitrión: `ip link set br-isp1 up` | Vuelve `ISP1=up ISP2=up` y la política normal |
| Zabbix | Dashboard desde PC-ADMIN01 | Gráficas de entrada y salida de ambos ISP |

El failover se provoca cortando el enlace fuera de R-EDGE: bajando el bridge en el anfitrión, desconectando el teléfono o apagando sus datos móviles. No apagues la interfaz dentro de R-EDGE con `ip link set down`, porque eso también borra sus rutas.

## 6. Estudiante 4: VPN WireGuard y DMZ

### 6.1 VPN-SRV: servidor WireGuard

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 10.10.50.2/28
    gateway 10.10.50.1
```

Claves y configuración base:

```bash
umask 077
mkdir -p /etc/wireguard/clients
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
```

`/etc/wireguard/wg0.conf`:

```ini
[Interface]
# Una interfaz con dos redes: VPN-ADMIN y VPN-USERS.
Address = 10.200.10.1/24, 10.200.20.1/24
ListenPort = 51820
PrivateKey = <contenido de /etc/wireguard/server.key>
```

No hay reglas de NAT a propósito: el tráfico sale de VPN-SRV con su IP `10.200.x.x` para que el firewall distinga VPN-ADMIN de VPN-USERS.

`/usr/local/sbin/wg-add-peer.sh` crea un peer, lo registra y genera el archivo del cliente:

```bash
#!/bin/bash
# Uso: wg-add-peer.sh <nombre> <admin|user> <ultimo_octeto> [full]
set -e
ENDPOINT="<IP_WAN_DE_R-EDGE>:51820"   # IP de R-EDGE en la red del teléfono 1 (ver 1.5)
nombre=$1; tipo=$2; octeto=$3; modo=${4:-split}

case "$tipo" in
  admin) red=10.200.10 ;;
  user)  red=10.200.20 ;;
  *) echo "tipo debe ser admin o user" >&2; exit 1 ;;
esac
ip="$red.$octeto"

# Split tunnel: solo las redes internas. Full tunnel: todo el tráfico.
if [[ "$modo" == full ]]; then permitidas="0.0.0.0/0"; else permitidas="10.10.0.0/16"; fi

umask 077
priv=$(wg genkey)
pub=$(echo "$priv" | wg pubkey)

cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
# $nombre ($tipo)
PublicKey = $pub
AllowedIPs = $ip/32
EOF

cat > "/etc/wireguard/clients/$nombre.conf" <<EOF
[Interface]
PrivateKey = $priv
Address = $ip/24
DNS = 8.8.8.8

[Peer]
PublicKey = $(cat /etc/wireguard/server.pub)
Endpoint = $ENDPOINT
AllowedIPs = $permitidas
PersistentKeepalive = 25
EOF

# Registro de peers configurados.
echo "$nombre,$tipo,$ip,$pub,$(date -Is)" >> /etc/wireguard/peers.csv

if ip link show wg0 >/dev/null 2>&1; then
  wg syncconf wg0 <(wg-quick strip wg0)
fi
echo "Peer $nombre creado: /etc/wireguard/clients/$nombre.conf"
```

```bash
chmod +x /usr/local/sbin/wg-add-peer.sh
systemctl enable --now wg-quick@wg0

wg-add-peer.sh admin1 admin 10
wg-add-peer.sh admin2 admin 11
wg-add-peer.sh user1  user  10
wg-add-peer.sh user2  user  11
wg-add-peer.sh user3  user  12 full     # peer de demostración de Full Tunnel
wg show
```

En el servidor, `AllowedIPs = <ip>/32` hace que cada peer solo pueda usar su propia dirección: un usuario no puede hacerse pasar por un administrador cambiando su IP. El archivo de `clients/` se copia al equipo remoto y se activa con `wg-quick up ./admin1.conf` o importándolo en la aplicación de WireGuard.

Con Full Tunnel, la navegación del peer sale por VPN-SRV → FW → R-EDGE, así que también pasa por el balanceo y el failover del Multi-WAN.

### 6.2 WEB01: servidor web de la DMZ

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 10.10.50.10/28
    gateway 10.10.50.1
    # Las respuestas a clientes VPN vuelven por VPN-SRV, no por el firewall.
    up ip route add 10.200.10.0/24 via 10.10.50.2
    up ip route add 10.200.20.0/24 via 10.10.50.2
```

Las dos rutas son necesarias porque VPN-SRV y WEB01 comparten segmento: un cliente VPN llega a WEB01 directamente, y sin ellas la respuesta iría al firewall, que la descartaría por no haber visto el inicio de la conexión.

```bash
echo "<h1>WEB01 - DMZ XelajuNetwork</h1>" > /var/www/html/index.html
systemctl enable --now nginx
```

WEB02 es igual con la dirección `10.10.50.11`.

### 6.3 ngrok

**Verificar** el método de instalación vigente en la documentación de ngrok; requiere una cuenta gratuita y su token.

```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" \
  > /etc/apt/sources.list.d/ngrok.list
apt update && apt install -y ngrok

ngrok config add-authtoken <TOKEN>
ngrok http 80
```

ngrok abre una conexión **saliente** por TCP 443 desde WEB01 hacia su nube y devuelve una URL pública. Los visitantes entran por esa URL y ngrok les reenvía el tráfico por el túnel ya abierto, por eso WEB01 no necesita IP pública ni reglas de entrada en el firewall.

### 6.4 Pruebas del estudiante 4

| Prueba | Comando | Resultado esperado |
|---|---|---|
| Túnel activo | `wg show` en VPN-SRV | Peer con `latest handshake` reciente |
| Admin a VLAN ADMIN | Peer admin1: `ping 10.10.10.10` | Responde |
| User a VLAN ADMIN | Peer user1: `ping 10.10.10.10` | Bloqueado (`FW-DENY` en FW) |
| User a SERVERS | Peer user1: `curl http://10.10.40.10` | Responde |
| Registro de peers | `cat /etc/wireguard/peers.csv` | Nombre, tipo, IP, clave pública |
| Full Tunnel | Peer user3: `curl ifconfig.me` | Muestra la IP pública de un ISP del proyecto |
| Web en DMZ | PC-ADMIN01: `curl http://10.10.50.10` | Página de WEB01 |
| ngrok | Abrir la URL pública desde un teléfono con datos | Página de WEB01 |
| Sin IP pública | `ip -4 addr` en WEB01 | Solo 10.10.50.10 |

## 7. Estudiante 5: firewall, IDS y análisis de tráfico

### 7.1 Red de FW

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 10.10.0.2/30
    gateway 10.10.0.1

auto eth1
iface eth1 inet static
    address 10.10.0.5/30
    up ip route add 10.10.0.8/30  via 10.10.0.6
    up ip route add 10.10.10.0/27 via 10.10.0.6
    up ip route add 10.10.20.0/25 via 10.10.0.6
    up ip route add 10.10.30.0/28 via 10.10.0.6
    up ip route add 10.10.40.0/27 via 10.10.0.6

auto eth2
iface eth2 inet static
    address 10.10.50.1/28
    up ip route add 10.200.10.0/24 via 10.10.50.2
    up ip route add 10.200.20.0/24 via 10.10.50.2
```

### 7.2 Firewall nftables

`/etc/nftables.conf` en FW:

```
#!/usr/sbin/nft -f
flush ruleset

define WAN    = "eth0"
define INSIDE = "eth1"
define DMZ    = "eth2"

define ADMIN     = 10.10.10.0/27
define USERS     = 10.10.20.0/25
define SERVERS   = 10.10.40.0/27
define ZABBIX    = 10.10.30.2
define PROXY     = 10.10.0.6
define REDGE     = 10.10.0.1
define DMZ_NET   = 10.10.50.0/28
define VPN_SRV   = 10.10.50.2
define WEB       = { 10.10.50.10, 10.10.50.11 }
define VPN_ADMIN = 10.200.10.0/24
define VPN_USERS = 10.200.20.0/24

table inet fw {
  chain input {
    type filter hook input priority filter; policy drop;
    ct state established,related accept
    ct state invalid drop
    iifname "lo" accept
    ip saddr { $ADMIN, $VPN_ADMIN } tcp dport 22 log prefix "FW-ALLOW " accept
    ip saddr { $ADMIN, $VPN_ADMIN } icmp type echo-request accept
    log prefix "FW-DENY " drop
  }

  chain forward {
    type filter hook forward priority filter; policy drop;

    # Seguimiento de conexiones: el retorno de lo ya permitido pasa.
    ct state established,related accept
    ct state invalid drop

    # Internet -> servidor VPN (tras el DNAT de R-EDGE).
    iifname $WAN ip daddr $VPN_SRV udp dport 51820 log prefix "FW-ALLOW " accept

    # Redes internas -> Internet.
    iifname $INSIDE oifname $WAN ip saddr { $ADMIN, $USERS, $SERVERS } tcp dport { 80, 443 } log prefix "FW-ALLOW " accept
    iifname $INSIDE oifname $WAN ip saddr { $ADMIN, $USERS, $SERVERS, $PROXY } meta l4proto { tcp, udp } th dport 53 log prefix "FW-ALLOW " accept
    iifname $INSIDE oifname $WAN ip saddr $ADMIN icmp type echo-request log prefix "FW-ALLOW " accept

    # Monitoreo entre Zabbix y R-EDGE.
    ip saddr $ZABBIX ip daddr $REDGE tcp dport 10050 log prefix "FW-ALLOW " accept
    ip saddr $ZABBIX ip daddr $REDGE icmp type echo-request accept
    ip saddr $REDGE ip daddr $ZABBIX tcp dport 10051 log prefix "FW-ALLOW " accept

    # Redes internas -> DMZ.
    iifname $INSIDE oifname $DMZ ip saddr $ADMIN ip daddr $DMZ_NET tcp dport { 22, 80, 443 } log prefix "FW-ALLOW " accept
    iifname $INSIDE oifname $DMZ ip saddr $ADMIN ip daddr $DMZ_NET icmp type echo-request accept
    iifname $INSIDE oifname $DMZ ip saddr $USERS ip daddr $WEB tcp dport { 80, 443 } log prefix "FW-ALLOW " accept

    # DMZ -> Internet: túnel de ngrok y DNS.
    iifname $DMZ oifname $WAN ip saddr $WEB tcp dport 443 log prefix "FW-ALLOW " accept
    iifname $DMZ oifname $WAN ip saddr $WEB meta l4proto { tcp, udp } th dport 53 log prefix "FW-ALLOW " accept

    # VPN-ADMIN -> redes internas.
    iifname $DMZ oifname $INSIDE ip saddr $VPN_ADMIN ip daddr { $ADMIN, $SERVERS, $USERS } log prefix "FW-ALLOW " accept
    iifname $DMZ oifname $INSIDE ip saddr $VPN_ADMIN ip daddr $ZABBIX tcp dport { 80, 443 } log prefix "FW-ALLOW " accept

    # VPN-USERS -> redes internas.
    iifname $DMZ oifname $INSIDE ip saddr $VPN_USERS ip daddr $ADMIN log prefix "FW-DENY " drop
    iifname $DMZ oifname $INSIDE ip saddr $VPN_USERS ip daddr $SERVERS tcp dport { 80, 443 } log prefix "FW-ALLOW " accept
    iifname $DMZ oifname $INSIDE ip saddr $VPN_USERS ip daddr $USERS log prefix "FW-ALLOW " accept

    # VPN -> Internet (Full Tunnel).
    iifname $DMZ oifname $WAN ip saddr { $VPN_ADMIN, $VPN_USERS } tcp dport { 80, 443 } log prefix "FW-ALLOW " accept
    iifname $DMZ oifname $WAN ip saddr { $VPN_ADMIN, $VPN_USERS } meta l4proto { tcp, udp } th dport 53 log prefix "FW-ALLOW " accept

    # Denegación por defecto, registrada.
    log prefix "FW-DENY " drop
  }
}
```

```bash
nft -c -f /etc/nftables.conf      # valida sin aplicar
systemctl enable --now nftables
```

Puntos para la explicación:

- **Denegación por defecto:** `policy drop` más la última regla; solo pasa lo que una regla permite de forma explícita.
- **Seguimiento de conexiones:** las reglas solo evalúan el primer paquete (`new`); el resto de la conexión pasa por `established,related`. Por eso cada conexión genera una sola línea de log.
- **Sin duplicar las ACL del estudiante 1:** aquí no hay reglas entre VLANs; ese tráfico nunca llega a FW.
- **ngrok:** no hay regla de entrada desde Internet hacia la DMZ; basta la salida por 443 de WEB01.

### 7.3 Registros de seguridad

`/etc/rsyslog.d/30-firewall.conf`:

```
:msg, contains, "FW-" /var/log/firewall/fw.log
& stop
```

```bash
mkdir -p /var/log/firewall
chown root:adm /var/log/firewall && chmod 750 /var/log/firewall
touch /var/log/firewall/fw.log
chown root:adm /var/log/firewall/fw.log && chmod 640 /var/log/firewall/fw.log
systemctl restart rsyslog
```

Cada línea incluye fecha y hora, acción (`FW-ALLOW` o `FW-DENY`), IP de origen (`SRC`), destino (`DST`), protocolo (`PROTO`) y puerto (`DPT`). Solo `root` y los miembros del grupo `adm` pueden leer el archivo; los administradores se añaden con `usermod -aG adm <usuario>`.

**Verificar** que el archivo conserve los permisos tras la primera escritura de rsyslog (`ls -l /var/log/firewall`).

### 7.4 IDS con Suricata

En `/etc/suricata/suricata.yaml` ajusta estos bloques:

```yaml
vars:
  address-groups:
    HOME_NET: "[10.10.0.0/16,10.200.0.0/16]"
    EXTERNAL_NET: "!$HOME_NET"

af-packet:
  - interface: eth0
  - interface: eth1
  - interface: eth2

default-rule-path: /etc/suricata/rules
rule-files:
  - local.rules
```

`/etc/suricata/rules/local.rules`:

```
alert tcp any any -> $HOME_NET any (msg:"XELAJU Posible escaneo de puertos"; flags:S; threshold:type threshold, track by_src, count 20, seconds 5; classtype:attempted-recon; sid:1000001; rev:1;)
alert tcp any any -> $HOME_NET 22 (msg:"XELAJU Multiples intentos de conexion SSH"; flags:S; threshold:type threshold, track by_src, count 5, seconds 30; classtype:attempted-admin; sid:1000002; rev:1;)
alert http any any -> any any (msg:"XELAJU Firma de prueba en URI"; flow:established,to_server; http.uri; content:"prueba-ids"; nocase; classtype:policy-violation; sid:1000003; rev:1;)
```

```bash
suricata -T -c /etc/suricata/suricata.yaml     # prueba la configuración y las reglas
systemctl enable --now suricata
tail -f /var/log/suricata/fast.log             # alertas
```

Las tres reglas cubren los tres ejemplos del enunciado: escaneo de puertos (20 SYN en 5 s desde un mismo origen), múltiples intentos de conexión (5 SYN a SSH en 30 s) y una firma definida (la cadena `prueba-ids` en una URL). Suricata corre en FW porque por ahí pasa todo el tráfico entre zonas.

### 7.5 Wireshark y punto de captura

- **Captura en el firewall:** `tcpdump -ni eth2 -w /tmp/dmz.pcap` en FW; el archivo se copia a un cliente con Wireshark (`scp`). FW es un punto de captura válido porque el tráfico lo atraviesa.
- **Tráfico que cruza el switch:** el puerto `eth7` de SW1 es un SPAN que copia la troncal (sección 3.1). Se conecta un cliente con Wireshark a ese puerto y se captura allí. El modo promiscuo solo no bastaría: un switch no entrega a un puerto las tramas de otros equipos.

Captura sugerida para la entrega: el saludo de WireGuard (UDP 51820) en `eth0` de FW, o una solicitud HTTP a WEB01 con las etiquetas 802.1Q visibles en el SPAN.

### 7.6 Pruebas del estudiante 5

| Prueba | Comando | Resultado esperado |
|---|---|---|
| Reglas activas | `nft list ruleset` en FW | Política `drop` en `input` y `forward` |
| Permitido | PC-ADMIN01: `curl http://10.10.50.10` | Responde; `FW-ALLOW` en `fw.log` |
| Denegado | PC-USER01: `ssh 10.10.50.10` | Bloqueado; `FW-DENY` en `fw.log` |
| DMZ aislada | WEB01: `ping 10.10.10.10` | Bloqueado |
| Políticas VPN | Pruebas de la sección 6.4 | Coinciden con la matriz |
| Logs protegidos | `cat /var/log/firewall/fw.log` con un usuario común | Permiso denegado |
| Escaneo | PC-ADMIN01: `nmap -sS 10.10.50.10` | Alerta sid 1000001 en `fast.log` |
| Firma | PC-ADMIN01: `curl http://10.10.50.10/prueba-ids` | Alerta sid 1000003 |
| Wireshark | Captura en el SPAN o en FW | Comunicación analizada con capturas de pantalla |

## 8. Pruebas de integración

| Flujo | Prueba | Componentes que demuestra |
|---|---|---|
| A: navegación | PC-USER01 abre un sitio permitido y uno bloqueado | ACL de R2, Squid, firewall, Multi-WAN |
| A: failover | Repetir con ISP1 caído (`br-isp1` abajo en el anfitrión) | Failover y recuperación |
| B: VPN | Peer admin1 y peer user1 acceden a las VLAN | WireGuard, DNAT de R-EDGE, políticas de FW |
| C: ngrok | Un usuario externo abre la URL pública | DMZ, salida controlada por FW y Multi-WAN |
| Monitoreo | Dashboard de Zabbix durante las pruebas | Métricas de ISP1 e ISP2 |

## 9. Diagnóstico rápido

| Síntoma | Qué revisar |
|---|---|
| Dos VM del mismo segmento no se ven | En el anfitrión: `bridge link` (cada tap en su bridge), MAC únicas, y `sysctl net.bridge.bridge-nf-call-iptables` en 0 si existe |
| R-EDGE sin salida por un ISP | Anclaje USB activo en el teléfono, su interfaz dentro del bridge (`bridge link` en el anfitrión) y que la red del teléfono no haya cambiado |
| Sin ping entre equipos de la misma VLAN | `bridge vlan show` en SW1 |
| Sin ping entre VLANs | `ip_forward` en R2 y `nft list ruleset` |
| VLAN sin Internet | Rutas de retorno en PROXY y FW; `ip route get 8.8.8.8` en cada salto |
| Web no carga pero el ping sí | `systemctl status squid`, `ip rule`, `ip route show table 100` y `rp_filter` en PROXY |
| Internet intermitente | `journalctl -t multiwan`; gateways reales en `mwan.conf` |
| VPN sin handshake | DNAT en R-EDGE, regla UDP 51820 en FW, `Endpoint` del cliente |
| VPN conecta pero no llega a las VLAN | Rutas a `10.200.x.x` en FW y `ip_forward` en VPN-SRV |
| Algo bloqueado sin saber dónde | `fw.log` en FW y `journalctl -k \| grep ACL-DENY` en R2 |
