# XelajuNetwork: guía de configuración por componente

Esta guía aplica el plan de `direccionamiento.md`. Todas las direcciones, rutas y reglas salen de ese archivo; si cambian allí, hay que cambiarlas aquí. Las pruebas de cada fase se registran en `bitacora-pruebas.md`.

> **Estado:** estas configuraciones no se han ejecutado todavía en los equipos reales. Sí se validaron en un contenedor Debian 13 con las herramientas reales:
>
> - **Sintaxis:** las reglas de nftables de R2, PROXY y FW, `squid.conf`, `dhcpd.conf` con sus reservas, las reglas de Suricata y todos los scripts.
> - **Funcionamiento del proxy:** intercepción con TPROXY, bloqueo por lista en HTTP y HTTPS, registro y recarga de listas, contra sitios reales.
> - **Lógica del Multi-WAN:** generación de reglas desde `politicas.conf` y los cambios de rutas del failover, con interfaces simuladas.
> - **Open vSwitch y WireGuard:** creación de puertos, VLAN y espejo, y el script de peers, sin tráfico real.
>
> - **Firewall (FW):** ya está configurado en su equipo real, y sus reglas se probaron allí con vecinos simulados (sección 7.2).
>
> No se ha probado nada con los enlaces físicos, los teléfonos ni el recorrido completo entre equipos. Hay que montarlo en el orden de la sección 2.3; los puntos con más riesgo están marcados con **Verificar**.
>
> El enunciado exige que cada integrante pueda explicar su parte. Cada sección dice qué hace cada bloque para que sirva de base a esa explicación.

## 1. Entorno de ejecución

No se usa GNS3. Cada nodo es una máquina virtual QEMU/KVM con Debian 13, o un equipo físico con Debian instalado en modo texto como sistema principal. Las VM se conectan entre sí con bridges Linux creados en el equipo anfitrión: cada segmento de red de la topología es un bridge, y cada interfaz de una VM es una interfaz virtual (tap) conectada a su bridge. La LAN interna es la excepción: su switch (SW1) es un Open vSwitch en el anfitrión del estudiante 1, que usa Ubuntu con autorización del catedrático.

### 1.1 Nodos

| Nodo | Dónde se ejecuta | Modo | Interfaces | RAM sugerida |
|---|---|---|---|---|
| R-EDGE | VM QEMU Debian 13 | Texto | 3 | 512 MB |
| FW | Equipo físico con Debian | Texto | 3 | — |
| PROXY | Equipo físico con Debian | Texto | 2 | — |
| R2 | VM QEMU Debian 13 | Texto | 2 | 512 MB |
| SW1 | Open vSwitch en el anfitrión Ubuntu del estudiante 1 (no es una VM) | Consola | 6 puertos + espejo | — |
| ZABBIX | VM QEMU Debian 13 | Texto (su interfaz web se usa desde un cliente) | 1 | 2 GB |
| VPN-SRV | VM QEMU Debian 13 | Texto | 1 | 256 MB |
| WEB01 / WEB02 | VM QEMU Debian 13 | Texto | 1 | 256 MB |
| SRV01 | VM QEMU Debian 13 | Texto | 1 | 256 MB |
| PC-ADMIN01, PC-USER01 | VM QEMU Debian 13 con escritorio XFCE | Gráfico (permitido para clientes) | 1 | 2 GB |
| PC-USER02 | VM QEMU Debian 13 | Texto | 1 | 512 MB |
| PC-REMOTO (cliente VPN) | VM QEMU Debian con escritorio en el anfitrión del estudiante 3, conectada a `br-isp1` (ver 1.5) | Gráfico | 1 | 2 GB |
| Anfitrión | Equipo Linux que ejecuta QEMU y los bridges | — | — | — |

### 1.2 Bridges de cada anfitrión

Cada anfitrión crea solo los bridges de los segmentos que tocan sus VM:

| Bridge | Anfitrión | Segmento | Interfaces conectadas |
|---|---|---|---|
| br-isp1 | Estudiante 3 | ISP1 | R-EDGE eth0, interfaz USB del teléfono 1, PC-REMOTO |
| br-isp2 | Estudiante 3 | ISP2 | R-EDGE eth1, interfaz USB del teléfono 2 |
| br-edge-fw | Estudiante 3 | 10.10.0.0/30 | R-EDGE eth2, interfaz Ethernet del cable hacia FW |
| br-proxy-r2 | Estudiante 1 | 10.10.0.8/30 | R2 eth0, interfaz Ethernet del cable hacia PROXY |
| br-dmz | Estudiante 4 | 10.10.50.0/28 | VPN-SRV, WEB01, WEB02, interfaz Ethernet del cable hacia FW |

El enlace FW – PROXY (`10.10.0.4/30`) no usa bridge: los dos son equipos físicos y se conectan con un cable directo.

La LAN interna tampoco usa bridges Linux: R2 y los equipos de las VLAN se conectan a puertos de SW1, el Open vSwitch del anfitrión del estudiante 1. Sus puertos están en la sección 3.1.

### 1.3 Red de cada anfitrión

`/usr/local/sbin/lab-net.sh` es el mismo script en los tres anfitriones; solo cambian sus dos variables:

```bash
#!/bin/bash
# Crea los bridges de este anfitrión y les une sus interfaces físicas.
# Ajusta BRIDGES y UNIONES según la tabla de abajo.
set -e
BRIDGES="br-isp1 br-isp2 br-edge-fw"
UNIONES="usb0:br-isp1 usb1:br-isp2 enp3s0:br-edge-fw"     # pares interfaz:bridge

for br in $BRIDGES; do
  ip link add "$br" type bridge 2>/dev/null || true
  ip link set "$br" up
done

# Cada interfaz se une a su bridge sin IP en el anfitrión, de modo que
# solo las VM usan ese enlace.
for par in $UNIONES; do
  ifc=${par%%:*}; br=${par##*:}
  ip addr flush dev "$ifc"
  ip link set "$ifc" master "$br"
  ip link set "$ifc" up
done
```

| Anfitrión | `BRIDGES` | `UNIONES` |
|---|---|---|
| Estudiante 3 | `br-isp1 br-isp2 br-edge-fw` | teléfono 1 a `br-isp1`, teléfono 2 a `br-isp2`, Ethernet del cable hacia FW a `br-edge-fw` |
| Estudiante 1 | `br-proxy-r2` | Ethernet del cable hacia PROXY a `br-proxy-r2` |
| Estudiante 4 | `br-dmz` | Ethernet del cable hacia FW a `br-dmz` |

Los nombres de interfaz (`usb0`, `enp3s0`, …) son ejemplos; los reales se ven con `ip link`. La interfaz que se une a un bridge pierde su IP en el anfitrión, así que el anfitrión debe tener su propia conexión por otra interfaz si la necesita.

`/etc/qemu/bridge.conf` en cada anfitrión, para que QEMU pueda conectar las VM a los bridges:

```
allow all
```

**Teléfonos (anfitrión del estudiante 3).** Los dos ISP son dos teléfonos celulares conectados por USB al anfitrión, con el anclaje de red por USB activado. Cada teléfono aparece como una interfaz de red (`usb0`, `usb1` o un nombre del tipo `enx…`). Antes de ejecutar el script hay que anotar la red de cada teléfono, porque después el anfitrión ya no tendrá IP en ellas:

1. Conecta el primer teléfono y activa el anclaje por USB.
2. Ejecuta `ip -4 addr show` e `ip route` en el anfitrión, y anota la interfaz, la IP y máscara recibidas y el gateway (la IP del teléfono).
3. Repite con el segundo teléfono.
4. Comprueba que las dos redes sean distintas.

Las direcciones WAN de R-EDGE dependen de cada teléfono. En esta guía aparecen como marcadores: `192.168.41.x` para ISP1 y `192.168.42.x` para ISP2. En cada enlace, R-EDGE usa una IP fija de la red del teléfono, configurada a mano, y el gateway es la IP del teléfono. Conviene elegir una IP alta de la red (por ejemplo, terminada en `.200`), porque el teléfono reparte las bajas por DHCP a otros equipos, como PC-REMOTO.

**Verificar:**

- **Redes distintas:** dos teléfonos del mismo tipo pueden entregar la misma red (por ejemplo, los iPhone suelen usar `172.20.10.0/28`). R-EDGE no debe tener sus dos WAN en la misma subred; si coinciden, usa otro modelo de teléfono.
- **Red estable:** algunos teléfonos cambian de red cada vez que se reactiva el anclaje. Tras cada reconexión, confirma que la red sigue siendo la anotada; si cambió, actualiza R-EDGE.
- **Gestor de red del anfitrión:** no debe volver a pedir IP en las interfaces unidas a un bridge; si lo hace, márcalas como no gestionadas.

### 1.4 Creación y arranque de las VM

Cada VM usa un disco propio derivado de una imagen base de Debian 13 ya instalada, con consola serial habilitada:

```bash
mkdir -p /var/lib/xelaju
qemu-img create -f qcow2 -F qcow2 -b /ruta/a/debian13-base.qcow2 /var/lib/xelaju/R2.qcow2
```

`/usr/local/sbin/vm.sh` en el anfitrión:

```bash
#!/bin/bash
# Uso: vm.sh <nombre> <id> <ram_MB> <red>...
# Cada <red> es un bridge Linux (br-dmz) o un puerto ya creado de SW1 (tap:tap-r2).
# La primera interfaz de la VM (eth0) usa la primera <red>, y así sucesivamente.
nombre=$1; id=$2; ram=$3; shift 3

red=(); i=0
for br in "$@"; do
  mac=$(printf '52:54:00:00:%02x:%02x' "$id" "$i")   # MAC única por VM e interfaz
  if [[ "$br" == tap:* ]]; then
    conexion="tap,id=n$i,ifname=${br#tap:},script=no,downscript=no"
  else
    conexion="bridge,id=n$i,br=$br"
  fi
  red+=(-netdev "$conexion" -device "e1000,netdev=n$i,mac=$mac")
  i=$((i + 1))
done

if [[ -n "${GUI:-}" ]]; then pantalla=(-display gtk); else pantalla=(-nographic); fi

exec qemu-system-x86_64 -enable-kvm -name "$nombre" -m "$ram" \
  -drive "file=/var/lib/xelaju/$nombre.qcow2,if=ide" \
  "${pantalla[@]}" "${red[@]}"
```

Arranque de cada nodo en el anfitrión de su encargado, como root y cada uno en su propia terminal (o en ventanas de `tmux`). El estudiante 4 gestiona sus VM con libvirt en lugar de `vm.sh`; lo que importa es que su interfaz quede en `br-dmz`.

```bash
# Anfitrión del estudiante 3
vm.sh R-EDGE    1  512  br-isp1 br-isp2 br-edge-fw
GUI=1 vm.sh PC-REMOTO 14 2048 br-isp1        # cliente VPN en el lado WAN; solo para esa prueba

# Anfitrión del estudiante 1 (después de sw1-ovs.sh, sección 3.1)
vm.sh R2        4  512  br-proxy-r2 tap:tap-r2
vm.sh ZABBIX    7  2048 tap:tap-zabbix
vm.sh SRV01     8  256  tap:tap-srv01
GUI=1 vm.sh PC-ADMIN01 11 2048 tap:tap-admin01
GUI=1 vm.sh PC-USER01  12 2048 tap:tap-user01
vm.sh PC-USER02        13 512  tap:tap-user02

# Anfitrión del estudiante 4 (o sus equivalentes en libvirt)
vm.sh VPN-SRV   9  256  br-dmz
vm.sh WEB01     10 256  br-dmz

# FW y PROXY son equipos físicos: no se arrancan con vm.sh.
```

La MAC de cada interfaz sale del `id`: PC-USER01 tiene `52:54:00:00:0c:00` y PC-USER02 `52:54:00:00:0d:00`. Son las que se registran en el DHCP restringido. Sin MAC explícita, todas las VM de QEMU arrancarían con la misma y la red fallaría.

### 1.5 Notas del entorno

- **Nombres de interfaz:** la guía usa `eth0`, `eth1`, … Si Debian las nombra `ens3` o `enp0s3`, añade `net.ifnames=0 biosdevname=0` a `GRUB_CMDLINE_LINUX` en `/etc/default/grub`, ejecuta `update-grub` y reinicia; o sustituye los nombres en cada archivo.
- **SW1 como Open vSwitch:** el enunciado pide configurar los switches por consola, y Open vSwitch se administra con `ovs-vsctl`. Corre en el anfitrión del estudiante 1, que usa Ubuntu; el catedrático autorizó Ubuntu para este equipo.
- **Varios equipos físicos:** cada integrante trabaja en su propio equipo, así que los segmentos que unen dos componentes cruzan de una máquina a otra por cable. En cada extremo, la interfaz Ethernet física se une al bridge de ese segmento (`ip link set <interfaz> master br-proxy-r2`), o es directamente la interfaz del nodo si este es un equipo físico. Por ejemplo, `eth0` de R2 sale por `br-proxy-r2` en el anfitrión del estudiante 1 y llega por cable al PROXY, que es un equipo físico. Los bridges de cada anfitrión están en la sección 1.2.
- **Debian como sistema principal:** si un nodo es un equipo físico, necesita tantas interfaces de red como indica la tabla (adaptadores USB-Ethernet si faltan). Es el caso de FW y PROXY; sus nombres reales de interfaz sustituyen a `eth0`, `eth1`, … (secciones 4.2 y 7.1).
- **Consumo de datos:** todo el tráfico del laboratorio sale por datos móviles. Instala los paquetes antes (sección 2.1) y evita descargas grandes durante las pruebas.
- **Sin IP pública (cliente VPN):** las redes móviles casi siempre usan CGNAT, así que un cliente no podrá iniciar la VPN desde Internet. Como el enlace USB solo une el teléfono con R-EDGE, el cliente "remoto" debe conectarse al lado WAN: usa la VM PC-REMOTO en `br-isp1`, en el anfitrión del estudiante 3 (sección 1.4). Toma su IP por DHCP del teléfono 1, usa un perfil de WireGuard entregado por el estudiante 4 y tiene como `Endpoint` la IP WAN de R-EDGE en esa red. Un equipo real fuera del laboratorio solo sirve si algún teléfono tiene IP pública.
- **Wireshark:** se ejecuta en el anfitrión de SW1 capturando en `span0`, el puerto espejo del switch (sección 3.1).

### 1.6 Reparto real por equipos y cableado

Cada integrante monta su componente en su propio equipo. La tabla recoge lo que cada uno ha informado.

| Encargado | Equipo real | Nodos que aloja |
|---|---|---|
| Estudiante 1 | Anfitrión Ubuntu con QEMU/KVM y Open vSwitch | R2, SW1, PC-ADMIN01, PC-USER01, PC-USER02, ZABBIX, SRV01 |
| Estudiante 2 | Equipo físico con Debian y NetworkManager | PROXY |
| Estudiante 3 | Anfitrión con una VM QEMU Debian en modo texto, y los dos teléfonos conectados por USB al anfitrión | R-EDGE |
| Estudiante 4 | Anfitrión con VM QEMU/KVM gestionadas con libvirt | VPN-SRV, WEB01, clientes VPN de prueba |
| Estudiante 5 | Equipo físico con Debian en modo texto | FW |

Los segmentos que unen componentes de dos equipos son cables Ethernet:

| Enlace | Red | Un extremo | Otro extremo |
|---|---|---|---|
| R-EDGE – FW | 10.10.0.0/30 | Interfaz física del anfitrión del estudiante 3, unida a `br-edge-fw` | FW `enp3s0` |
| FW – PROXY | 10.10.0.4/30 | FW `enx00e04c360188` | PROXY `enp0s31f6` |
| PROXY – R2 | 10.10.0.8/30 | PROXY `enx9c69d3101d16` | Interfaz física del anfitrión del estudiante 1, unida a `br-proxy-r2` |
| FW – DMZ | 10.10.50.0/28 | FW `enx00e04c3604ff` | Interfaz física del anfitrión del estudiante 4, unida a `br-dmz` |

Interfaces Ethernet físicas que necesita cada equipo (con adaptadores USB-Ethernet si faltan):

| Equipo | Interfaces | Para |
|---|---|---|
| Anfitrión del estudiante 3 | 1, más los dos teléfonos por USB | FW |
| FW | 3 | R-EDGE, PROXY, DMZ |
| PROXY | 2 | FW, R2 |
| Anfitrión del estudiante 1 | 1 | PROXY |
| Anfitrión del estudiante 4 | 1 | FW |

Cuando el nodo es una VM, la interfaz física del anfitrión se une al bridge del segmento y la VM se conecta a ese bridge. Cuando el nodo es un equipo físico, la interfaz física es directamente la del nodo y no hace falta bridge.

En toda la guía, los nombres `eth0`, `eth1`, … son los de una VM. En un equipo físico hay que sustituirlos por los nombres reales, tanto en la configuración de red como en las reglas de nftables.

## 2. Preparación común y orden de montaje

### 2.1 Paquetes

Los nodos no tendrán Internet hasta que toda la cadena funcione. Instala los paquetes antes de conectar la VM a sus bridges: arráncala una vez con la red de usuario de QEMU (añade `-nic user,model=e1000` al comando de QEMU y ejecuta `dhclient eth0` dentro), o instálalos en la imagen base antes de derivar los discos.

| Nodo | Paquetes |
|---|---|
| Todos | `nftables tcpdump curl` |
| R-EDGE | `conntrack zabbix-agent` |
| FW | `rsyslog suricata` |
| PROXY | `squid-openssl openssl python3 dnsmasq` |
| R2 | `vlan isc-dhcp-server` |
| Anfitrión de SW1 (Ubuntu) | `openvswitch-switch` |
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

Y aplícalo con `sysctl --system`. La red de cada nodo se define en `/etc/network/interfaces` y se aplica con `systemctl restart networking`; PROXY es la excepción, porque usa NetworkManager (sección 4.2).

Servidores DNS de cada equipo:

| Equipo | DNS | Motivo |
|---|---|---|
| Clientes de las VLAN 10 y 20 | `10.10.0.9` (PROXY) | Deben resolver con la misma caché que Squid (sección 4.4) |
| PROXY | `127.0.0.1` | Usa su propia caché DNS |
| Resto de nodos | `8.8.8.8` | No pasan por Squid |

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

SW1 es un Open vSwitch que corre en el anfitrión Ubuntu del estudiante 1; no es una VM. Se configura por consola con `ovs-vsctl`, y cada VM se conecta a uno de sus puertos mediante una interfaz tap.

Asignación de puertos:

| Puerto | Modo | VLAN | Conectado a |
|---|---|---|---|
| tap-r2 | Troncal 802.1Q | 10, 20, 30, 40 | R2 eth1 |
| tap-admin01 | Acceso | 10 | PC-ADMIN01 |
| tap-user01 | Acceso | 20 | PC-USER01 |
| tap-user02 | Acceso | 20 | PC-USER02 |
| tap-zabbix | Acceso | 30 | ZABBIX |
| tap-srv01 | Acceso | 40 | SRV01 |
| span0 | Espejo (SPAN) | — | Captura con Wireshark en el anfitrión |

`/usr/local/sbin/sw1-ovs.sh` en el anfitrión:

```bash
#!/bin/bash
# SW1: Open vSwitch en el anfitrión. Crea el switch, sus puertos y el espejo.
set -e
ovs-vsctl --may-exist add-br sw1

puerto() {   # $1 nombre del tap, $2 opción de VLAN (tag=N o trunks=...)
  ip tuntap add dev "$1" mode tap 2>/dev/null || true
  ip link set "$1" up
  ovs-vsctl --may-exist add-port sw1 "$1" -- set port "$1" "$2"
}

# Troncal: transporta las cuatro VLAN etiquetadas hacia R2.
puerto tap-r2 trunks=10,20,30,40

# Acceso: la trama entra sin etiqueta y se asigna a la VLAN (tag).
puerto tap-admin01 tag=10
puerto tap-user01  tag=20
puerto tap-user02  tag=20
puerto tap-zabbix  tag=30
puerto tap-srv01   tag=40

# SPAN: puerto interno que recibe una copia de todo el tráfico del switch.
ovs-vsctl --may-exist add-port sw1 span0 -- set interface span0 type=internal
ip link set span0 up
ovs-vsctl -- --id=@p get port span0 \
          -- --id=@m create mirror name=span select-all=true output-port=@p \
          -- set bridge sw1 mirrors=@m
```

El script debe ejecutarse antes de arrancar las VM, porque `vm.sh` se conecta a los tap que este crea. Para que se ejecute al arrancar, crea `/etc/systemd/system/sw1-ovs.service`. Este mismo patrón de unidad sirve para los demás scripts de la guía:

```ini
[Unit]
Description=Puertos y VLANs de SW1 (Open vSwitch)
After=network-online.target openvswitch-switch.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/sw1-ovs.sh

[Install]
WantedBy=multi-user.target
```

```bash
chmod +x /usr/local/sbin/sw1-ovs.sh
systemctl enable --now sw1-ovs.service
ovs-vsctl show            # comprobación: puertos con su tag o trunks
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
  option domain-name-servers 10.10.0.9;       # caché DNS de PROXY
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

Instalación con los paquetes de Debian 13 (Zabbix 7.0). Las rutas de los esquemas son las de ese paquete:

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

Restringe la interfaz web a la VLAN de Administración en `/etc/apache2/conf-available/zabbix-frontend-php.conf`, dentro del bloque `<Directory>` del frontend, y recarga Apache (`systemctl reload apache2`):

```apache
Require ip 10.10.10.0/27
```

Esta restricción se suma a la ACL de R2, que ya impide que USERS llegue a la VLAN 30. Después, desde PC-ADMIN01:

1. Abre `http://10.10.30.2/zabbix` y completa el asistente (usuario inicial `Admin`, clave `zabbix`; cámbiala).
2. Crea el host `R-EDGE` con interfaz de agente `10.10.0.1:10050` y la plantilla "Linux by Zabbix agent".
3. Crea un dashboard con gráficas de bits recibidos y enviados de `eth0` (ISP1) y `eth1` (ISP2).

### 3.6 Clientes de las VLAN

- **PC-ADMIN01:** estática `10.10.10.10/27`, gateway `10.10.10.1`, DNS `10.10.0.9` (PROXY).
- **SRV01:** estática `10.10.40.10/27`, gateway `10.10.40.1`; instala `nginx` para probar el acceso por 80/443.
- **PC-USER01 / PC-USER02:** DHCP (`iface eth0 inet dhcp` o el gestor de red del escritorio). Reciben por DHCP el DNS `10.10.0.9`.

### 3.7 Pruebas del estudiante 1

| Prueba | Comando | Resultado esperado |
|---|---|---|
| Troncal y VLANs | `ovs-vsctl show` en el anfitrión de SW1 | Puertos con su `tag` o `trunks` |
| Inter-VLAN permitido | `ping 10.10.40.10` desde PC-ADMIN01 | Responde |
| ACL bloquea | `ping 10.10.10.10` desde PC-USER01 | Sin respuesta, línea `ACL-DENY` en R2 |
| Servicio permitido | `curl http://10.10.40.10` desde PC-USER01 | Responde |
| Servicio denegado | `ssh 10.10.40.10` desde PC-USER01 | Bloqueado |
| DHCP registrado | `dhclient -v eth0` en PC-USER01 | Recibe siempre 10.10.20.10 |
| DHCP no registrado | Quitar a PC-USER02 de `usuarios.csv`, ejecutar `dhcp-reservas.sh` en R2 y pedir IP de nuevo en PC-USER02 | No recibe IP; en `journalctl -u isc-dhcp-server` de R2 hay DISCOVER sin OFFER. Al volver a registrarlo recibe 10.10.20.11 |

## 4. Estudiante 2: proxy Squid transparente

### 4.1 Cómo funciona

PROXY está en línea entre R2 y FW, así que todo el tráfico de las VLAN lo atraviesa. Por eso el desvío hacia Squid se hace en el propio PROXY: R2 no redirige nada, y no debe hacerlo, porque Squid necesita que el desvío ocurra en su misma máquina para conocer el destino original de cada conexión. Con TPROXY, el kernel desvía a Squid las conexiones web de ADMIN y USERS sin que el cliente configure nada, y Squid sale a Internet **conservando la IP del cliente como origen**. Eso último es lo que permite que el firewall y el Multi-WAN sigan aplicando reglas por IP de origen.

- **HTTP (puerto 80):** Squid lee la cabecera `Host` y aplica la lista.
- **HTTPS (puerto 443):** Squid no descifra. Lee el nombre del sitio en el SNI del saludo TLS (`peek`); si está en la lista corta la conexión (`terminate`), y si no la deja pasar intacta (`splice`).
- **Caché DNS compartida:** antes de dejar pasar una conexión HTTPS, Squid comprueba que la IP de destino corresponda al nombre del sitio, resolviéndolo él mismo. Si el cliente y Squid preguntan a servidores DNS distintos, muchos sitios devuelven IPs diferentes a cada uno y Squid rechaza la conexión (error 409). Por eso PROXY ejecuta una caché DNS (`dnsmasq`) que usan tanto los clientes como Squid. En las pruebas, sin la caché falló cerca del 10 % de las conexiones HTTPS permitidas; con ella, ninguna.

### 4.2 Red y enrutamiento de PROXY

> **Equipo real del encargado.** PROXY es un equipo físico con NetworkManager, y sus interfaces no se llaman `eth0` y `eth1`:
>
> | En esta guía | Interfaz real | Perfil de NetworkManager | Hacia |
> |---|---|---|---|
> | `eth0` | `enp0s31f6` | `squid-firewall` | FW |
> | `eth1` | `enx9c69d3101d16` | `squid-r2` | R2 |
>
> Las direcciones, el gateway y las rutas a las VLAN ya están en esos perfiles. Faltan tres cosas, que NetworkManager no toma de `/etc/network/interfaces`:
>
> - **Reenvío:** `net.ipv4.ip_forward = 1` (sección 2.2), porque PROXY también enruta el tráfico que no es web.
> - **Reglas de TPROXY:** los dos comandos `ip rule` e `ip route … table 100` de abajo van en un script de arranque, con el patrón de unidad de la sección 3.1.
> - **Nombres reales:** en `nftables.conf` y en los `rp_filter`, sustituir `eth0` y `eth1` por los nombres reales.

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

Si Squid está detenido, las reglas de desvío no encuentran a quién entregar la conexión y el tráfico web pasa sin filtrar. Hay que comprobar que Squid esté activo antes de cada demostración (`systemctl status squid`).

### 4.4 Caché DNS y Squid

`/etc/dnsmasq.d/xelaju.conf` en PROXY:

```
# Caché DNS para los clientes de las VLAN y para Squid.
no-resolv
server=8.8.8.8
server=1.1.1.1
listen-address=127.0.0.1,10.10.0.9
bind-interfaces
cache-size=2000
min-cache-ttl=300
```

```bash
echo "nameserver 127.0.0.1" > /etc/resolv.conf
systemctl enable --now dnsmasq
```

`min-cache-ttl` mantiene cada respuesta al menos cinco minutos, para que el cliente y Squid vean la misma IP aunque el sitio la cambie con frecuencia.

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

# Squid resuelve con la caché DNS local, la misma que usan los clientes.
dns_nameservers 127.0.0.1

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
access_log stdio:/var/log/squid/access.log xelaju

cache deny all
visible_hostname proxy.xelaju.local
```

```bash
squid -k parse                    # valida la configuración
systemctl enable --now nftables
systemctl restart squid
```

Para cambiar una política durante la calificación: edita el archivo de lista y ejecuta `squid -k reconfigure`. No se toca `squid.conf`.

Squid debe ser el del paquete `squid-openssl`: `squid -v` tiene que mostrar `--with-openssl`. El paquete `squid` normal no acepta `ssl-bump`.

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
    blocked = "DENIED" in result or mode == "terminate"
    # Squid registra pasos intermedios de cada conexión HTTPS; solo interesa el final.
    if result.startswith("NONE_NONE/000") and not blocked:
        return None
    if sni != "-":
        domain = sni
    else:
        domain = urlparse(url if "://" in url else "//" + url).hostname or url
    if blocked:
        action = "BLOQUEADO"
    elif result.endswith("/409"):
        action = "ERROR"
    else:
        action = "PERMITIDO"
    return {"when": when, "src": src, "method": method, "domain": domain,
            "result": result, "action": action}


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
| DNS compartido | PC-USER01: `cat /etc/resolv.conf` | `nameserver 10.10.0.9` |
| Sin errores 409 | `grep -c '/409' /var/log/squid/access.log` tras navegar | 0 |

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
    up ip route add 10.200.10.0/28 via 10.10.0.2
    up ip route add 10.200.20.0/27 via 10.10.0.2
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
10.10.10.10, [80], TCP, ISP2
10.10.0.6, [53], UDP, ISP2
```

La línea de `10.10.10.10` con el puerto 80 muestra dos tipos de tráfico de un mismo equipo por proveedores distintos: su HTTP sale por ISP2 y su HTTPS, por ISP1 (regla de la VLAN de Administración).

Las consultas DNS de las VLAN 10 y 20 llegan a Internet con la IP de PROXY (`10.10.0.6`), porque las resuelve su caché; la última línea las envía por ISP2. La línea de `10.10.20.10` con el puerto 53 solo aplica si ese equipo consulta directamente a un servidor externo (por ejemplo, `dig @8.8.8.8`).

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
# Cada tabla conoce también la red de su propio enlace, para responder
# directamente a los equipos del lado WAN (por ejemplo, PC-REMOTO).
for par in "$ISP1_IF:101" "$ISP2_IF:102"; do
  ifc=${par%%:*}; tabla=${par##*:}
  ip -4 route show dev "$ifc" scope link | while read -r red _; do
    ip route replace "$red" dev "$ifc" table "$tabla"
  done
done
for p in 100 110 111; do ip rule del prio "$p" 2>/dev/null || true; done
ip rule add prio 100 to 10.0.0.0/8 lookup main        # destinos internos
ip rule add prio 110 fwmark 17 lookup 101             # sondeo de ISP1
ip rule add prio 111 fwmark 18 lookup 102             # sondeo de ISP2
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
  actual="$(sondeo "$ISP1_IF" 17) $(sondeo "$ISP2_IF" 18)"
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

Los sondeos usan marcas propias (17 y 18) que siempre apuntan a la tabla de su ISP. Van en decimal porque `ping -m` no acepta hexadecimal. Así el servicio puede detectar que un enlace volvió aunque en ese momento no tenga tráfico.

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

### Interfaces que usa este componente

El anfitrión del estudiante 4 necesita una sola interfaz física: su puerto Ethernet, conectado por cable a FW y unido al bridge `br-dmz`. Las demás interfaces son virtuales:

| Equipo | Interfaz | Tipo | Dirección |
|---|---|---|---|
| Anfitrión | Ethernet del cable hacia FW | Física, sin IP, unida a `br-dmz` | — |
| VPN-SRV | `eth0` | Virtual, en `br-dmz` | `10.10.50.2/28` |
| VPN-SRV | `wg0` | Túnel WireGuard | `10.200.10.1/28` y `10.200.20.1/27` |
| WEB01 | `eth0` | Virtual, en `br-dmz` | `10.10.50.10/28` |
| WEB02 (opcional) | `eth0` | Virtual, en `br-dmz` | `10.10.50.11/28` |

- **Una sola interfaz por VM:** VPN-SRV no necesita una segunda tarjeta. El tráfico cifrado entra por `eth0` y el descifrado sale por la misma `eth0` hacia FW.
- **Sin interfaz para ngrok:** el túnel sale por la `eth0` de WEB01, pasando por FW.
- **El Ethernet queda dedicado:** al unirlo al bridge pierde su IP en el anfitrión. Si el anfitrión necesita Internet propia, debe usar otra conexión, como la Wi-Fi.
- **Clientes VPN de prueba:** las VM de clientes del propio anfitrión no usan `br-dmz`. Para la prueba integrada, el cliente es PC-REMOTO, en el anfitrión del estudiante 3 (sección 1.5).

Con libvirt, cada VM se conecta a `br-dmz` así, quitando antes su interfaz de la red NAT por defecto:

```bash
virsh attach-interface --domain debian-wireguard --type bridge --source br-dmz --model virtio --config
```

Dentro de la VM, la interfaz puede llamarse `enp1s0` o similar en lugar de `eth0` (sección 1.5).

### 6.1 VPN-SRV: servidor WireGuard

> **Equipo real del encargado.** VPN-SRV es la VM `debian-wireguard`, gestionada con libvirt, y ya tiene `wg0` con sus claves y peers creados a mano. Para integrarla:
>
> - **Red de la VM:** su interfaz debe conectarse al bridge `br-dmz` del anfitrión (ver arriba), no a la red NAT por defecto de libvirt, y usar `10.10.50.2/28` con gateway `10.10.50.1`.
> - **Nombres de archivo:** sus claves están en `wg0-private.key` y `wg0-public.key`; esta guía las llama `server.key` y `server.pub`. Sirve cualquiera de los dos nombres mientras el script de peers use el mismo.
> - **Endpoint de los clientes:** usan el alias `vpn-multiwan` en `/etc/hosts`, que hoy apunta a la red de libvirt. En la integración debe apuntar a la IP WAN de R-EDGE.

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
Address = 10.200.10.1/28, 10.200.20.1/27
ListenPort = 51820
PrivateKey = <contenido de /etc/wireguard/server.key>
```

No hay reglas de NAT a propósito: el tráfico sale de VPN-SRV con su IP `10.200.x.x` para que el firewall distinga VPN-ADMIN de VPN-USERS.

`/usr/local/sbin/wg-add-peer.sh` crea un peer, lo registra y genera el archivo del cliente:

```bash
#!/bin/bash
# Uso: wg-add-peer.sh <nombre> <admin|user> <ultimo_octeto> [full]
# VPN-ADMIN: 10.200.10.0/28 (octetos 2 a 14). VPN-USERS: 10.200.20.0/27 (octetos 2 a 30).
set -e
ENDPOINT="<IP_WAN_DE_R-EDGE>:51820"   # IP de R-EDGE en la red del teléfono 1 (ver 1.5)
nombre=$1; tipo=$2; octeto=$3; modo=${4:-split}

case "$tipo" in
  admin) red=10.200.10; prefijo=28 ;;
  user)  red=10.200.20; prefijo=27 ;;
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
Address = $ip/$prefijo
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

wg show
```

Peers definidos por el encargado de la VPN (ya creados, con sus claves):

| Tipo | Peer | IP VPN |
|---|---|---|
| VPN-ADMIN (`10.200.10.0/28`) | local-admin1 | 10.200.10.2 |
| VPN-ADMIN | remote-admin1 a remote-admin6 | 10.200.10.3 a 10.200.10.8 |
| VPN-USERS (`10.200.20.0/27`) | local-user1 | 10.200.20.2 |
| VPN-USERS | remote-user1 a remote-user8 | 10.200.20.3 a 10.200.20.10 |

El script solo hace falta para peers nuevos, porque genera claves nuevas; no lo ejecutes sobre un peer que ya existe:

```bash
wg-add-peer.sh remote-admin7 admin 9
wg-add-peer.sh remote-user9  user  11 full     # peer de demostración de Full Tunnel
```

En los perfiles de cliente ya creados, `AllowedIPs` debe incluir las redes internas y no solo la red VPN; si no, el cliente levanta el túnel pero no llega a ninguna VLAN:

```ini
AllowedIPs = 10.10.0.0/16        # split tunnel: redes internas del proyecto
# AllowedIPs = 0.0.0.0/0         # full tunnel: todo el tráfico por la VPN
```

En el servidor, `AllowedIPs = <ip>/32` hace que cada peer solo pueda usar su propia dirección: un usuario no puede hacerse pasar por un administrador cambiando su IP. El archivo de `clients/` se copia al equipo remoto y se activa con `wg-quick up ./remote-admin1.conf` o importándolo en la aplicación de WireGuard.

Con Full Tunnel, la navegación del peer sale por VPN-SRV → FW → R-EDGE, así que también pasa por el balanceo y el failover del Multi-WAN.

### 6.2 WEB01: servidor web de la DMZ

`/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 10.10.50.10/28
    gateway 10.10.50.1
    # Las respuestas a clientes VPN vuelven por VPN-SRV, no por el firewall.
    up ip route add 10.200.10.0/28 via 10.10.50.2
    up ip route add 10.200.20.0/27 via 10.10.50.2
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
| Admin a VLAN ADMIN | Peer remote-admin1: `ping 10.10.10.10` | Responde |
| User a VLAN ADMIN | Peer remote-user1: `ping 10.10.10.10` | Bloqueado (`FW-DENY` en FW) |
| User a SERVERS | Peer remote-user1: `curl http://10.10.40.10` | Responde |
| Registro de peers | `cat /etc/wireguard/peers.csv` | Nombre, tipo, IP, clave pública |
| Full Tunnel | Peer con `AllowedIPs = 0.0.0.0/0`: `curl ifconfig.me` | Muestra la IP pública de un ISP del proyecto |
| Web en DMZ | PC-ADMIN01: `curl http://10.10.50.10` | Página de WEB01 |
| ngrok | Abrir la URL pública desde un teléfono con datos | Página de WEB01 |
| Sin IP pública | `ip -4 addr` en WEB01 | Solo 10.10.50.10 |

## 7. Estudiante 5: firewall, IDS y análisis de tráfico

### 7.1 Red de FW

> **Estado: aplicado en el equipo real.** FW es un equipo físico con Debian 13 en modo texto. Todo lo de esta sección 7 está instalado en él, y los archivos tal como quedaron están en la carpeta `fw/` del repositorio.

Interfaces reales de FW:

| Papel | Interfaz real | Dirección | Conectada por cable a |
|---|---|---|---|
| WAN | `enp3s0` (integrada) | `10.10.0.2/30` | R-EDGE (`br-edge-fw` en el anfitrión del estudiante 3) |
| Interna | `enx00e04c360188` (USB-Ethernet) | `10.10.0.5/30` | PROXY (`enp0s31f6`) |
| DMZ | `enx00e04c3604ff` (USB-Ethernet) | `10.10.50.1/28` | Anfitrión del estudiante 4 (`br-dmz`) |
| Gestión | `wlp4s0` (Wi-Fi) | DHCP | No forma parte de la topología |

La Wi-Fi da Internet propia al equipo (instalar paquetes, administrarlo) y no reenvía tráfico de la red: ninguna regla del firewall la menciona, así que todo lo que intentara cruzar por ella cae en la denegación por defecto.

Como la ruta por defecto del equipo es la de la Wi-Fi, la salida hacia R-EDGE del tráfico **reenviado** se define aparte, con enrutamiento por política:

- **Tabla 100:** contiene solo `default via 10.10.0.1` (R-EDGE).
- **Regla 100:** lo que entra por la interfaz interna o por la DMZ consulta primero la tabla principal sin su ruta por defecto, de modo que los destinos internos se resuelven con las rutas estáticas.
- **Regla 101:** si no hubo coincidencia, usa la tabla 100 y sale por R-EDGE.

`/etc/network/interfaces` (`fw/interfaces`):

```
auto lo
iface lo inet loopback

# Gestión: Wi-Fi con Internet propia del equipo (no forma parte de la topología).
allow-hotplug wlp4s0
iface wlp4s0 inet dhcp
    wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

# WAN: hacia R-EDGE (10.10.0.1). Sin "gateway": la salida del tráfico
# reenviado está en la tabla 100 (fw-rutas.sh).
allow-hotplug enp3s0
iface enp3s0 inet static
    address 10.10.0.2/30
    up /usr/local/sbin/fw-rutas.sh

# Interna: hacia PROXY (10.10.0.6).
allow-hotplug enx00e04c360188
iface enx00e04c360188 inet static
    address 10.10.0.5/30
    up ip route replace 10.10.0.8/30  via 10.10.0.6
    up ip route replace 10.10.10.0/27 via 10.10.0.6
    up ip route replace 10.10.20.0/25 via 10.10.0.6
    up ip route replace 10.10.30.0/28 via 10.10.0.6
    up ip route replace 10.10.40.0/27 via 10.10.0.6
    up /usr/local/sbin/fw-rutas.sh

# DMZ: VPN-SRV (10.10.50.2) y servidores web.
allow-hotplug enx00e04c3604ff
iface enx00e04c3604ff inet static
    address 10.10.50.1/28
    up ip route replace 10.200.10.0/28 via 10.10.50.2
    up ip route replace 10.200.20.0/27 via 10.10.50.2
    up /usr/local/sbin/fw-rutas.sh
```

`/usr/local/sbin/fw-rutas.sh` (`fw/fw-rutas.sh`):

```bash
#!/bin/bash
# FW: enrutamiento del tráfico reenviado (ver explicación arriba).
WAN=enp3s0
INSIDE=enx00e04c360188
DMZ=enx00e04c3604ff
REDGE=10.10.0.1

for pref in 100 101; do
  while ip rule del pref "$pref" 2>/dev/null; do :; done
done
for ifc in "$INSIDE" "$DMZ"; do
  ip rule add pref 100 iif "$ifc" lookup main suppress_prefixlength 0
  ip rule add pref 101 iif "$ifc" lookup 100
done
ip route replace default via "$REDGE" dev "$WAN" table 100 2>/dev/null || true
exit 0
```

Si se quita la Wi-Fi de gestión, basta con añadir `gateway 10.10.0.1` a `enp3s0`; el script puede quedarse.

### 7.2 Firewall nftables

`/etc/nftables.conf` en FW:

```
#!/usr/sbin/nft -f
flush ruleset

define WAN    = "enp3s0"
define INSIDE = "enx00e04c360188"
define DMZ    = "enx00e04c3604ff"

define ADMIN     = 10.10.10.0/27
define USERS     = 10.10.20.0/25
define SERVERS   = 10.10.40.0/27
define ZABBIX    = 10.10.30.2
define PROXY     = 10.10.0.6
define REDGE     = 10.10.0.1
define DMZ_NET   = 10.10.50.0/28
define VPN_SRV   = 10.10.50.2
define WEB       = { 10.10.50.10, 10.10.50.11 }
define VPN_ADMIN = 10.200.10.0/28
define VPN_USERS = 10.200.20.0/27
define VECINOS   = { 10.10.0.1, 10.10.0.6, 10.10.50.2 }

table inet fw {
  chain input {
    type filter hook input priority filter; policy drop;
    ct state established,related accept
    ct state invalid drop
    iifname "lo" accept
    ip saddr { $ADMIN, $VPN_ADMIN } tcp dport 22 log prefix "FW-ALLOW " accept
    ip saddr { $ADMIN, $VPN_ADMIN } icmp type echo-request accept
    # Ping de los equipos conectados directamente, para comprobar los enlaces.
    ip saddr $VECINOS icmp type echo-request accept
    # IPv6 de la Wi-Fi de gestión: descubrimiento de vecinos y de routers.
    meta l4proto ipv6-icmp accept
    # Difusión y multidifusión (ruido de red): se descarta sin registrar.
    meta pkttype { broadcast, multicast } drop
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

Las reglas cargadas se probaron en el propio equipo con `fw/prueba-reglas.sh`: el script crea vecinos simulados (R-EDGE, PROXY con los equipos de las VLAN, y la DMZ con los peers VPN) en espacios de red aislados, carga este mismo `nftables.conf` y comprueba 41 flujos de la matriz de seguridad, permitidos y bloqueados. Resultado: 41 de 41 correctos. No sustituye a la prueba con los equipos reales, pero confirma que las reglas hacen lo que dice la matriz.

Puntos para la explicación:

- **Denegación por defecto:** `policy drop` más la última regla; solo pasa lo que una regla permite de forma explícita.
- **Seguimiento de conexiones:** las reglas solo evalúan el primer paquete (`new`); el resto de la conexión pasa por `established,related`. Por eso cada conexión genera una sola línea de log.
- **Sin duplicar las ACL del estudiante 1:** aquí no hay reglas entre VLANs; ese tráfico nunca llega a FW.
- **ngrok:** no hay regla de entrada desde Internet hacia la DMZ; basta la salida por 443 de WEB01.

### 7.3 Registros de seguridad

`/etc/rsyslog.d/30-firewall.conf`:

```
# Registros del firewall: solo mensajes del kernel (nftables) con prefijo FW-.
if ($syslogfacility-text == "kern" and $msg contains "FW-") then {
    action(type="omfile" file="/var/log/firewall/fw.log" fileOwner="root" fileGroup="adm" fileCreateMode="0640")
    stop
}
```

El filtro exige que el mensaje venga del kernel. Sin esa condición, cualquier otro mensaje que contenga "FW-" (por ejemplo, el registro de un comando `sudo grep FW-DENY …`) acabaría en el archivo de auditoría.

```bash
mkdir -p /var/log/firewall
chown root:adm /var/log/firewall && chmod 750 /var/log/firewall
touch /var/log/firewall/fw.log
chown root:adm /var/log/firewall/fw.log && chmod 640 /var/log/firewall/fw.log
systemctl restart rsyslog
```

Cada línea incluye fecha y hora, acción (`FW-ALLOW` o `FW-DENY`), IP de origen (`SRC`), destino (`DST`), protocolo (`PROTO`) y puerto (`DPT`). Solo `root` y los miembros del grupo `adm` pueden leer el archivo; los administradores se añaden con `usermod -aG adm <usuario>`.

Comprobado en el equipo: tras escribir rsyslog, el archivo sigue como `root:adm` con modo `640`, y un usuario común recibe "permiso denegado". La rotación semanal está en `/etc/logrotate.d/firewall` (`fw/logrotate-firewall`).

### 7.4 IDS con Suricata

En `/etc/suricata/suricata.yaml` cambia estos valores. El archivo ya trae los cuatro bloques: `HOME_NET` y `EXTERNAL_NET` están al inicio; en `af-packet` hay una entrada `- interface: eth0` que se sustituye por las tres interfaces de FW; y `default-rule-path` con `rule-files` están al final, apuntando a `/var/lib/suricata/rules` y `suricata.rules`.

```yaml
vars:
  address-groups:
    HOME_NET: "[10.10.0.0/16,10.200.0.0/16]"
    EXTERNAL_NET: "!$HOME_NET"

af-packet:
  - interface: enx00e04c3604ff     # DMZ
    cluster-id: 97
    cluster-type: cluster_flow
    defrag: yes
  - interface: enx00e04c360188     # interna
    cluster-id: 98
    cluster-type: cluster_flow
    defrag: yes
  - interface: enp3s0              # WAN (entrada original, cluster-id 99)

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

Los cambios exactos sobre el archivo original están en `fw/suricata.yaml.diff`. Suricata arranca en el equipo con las tres interfaces y las tres reglas cargadas; las alertas no se han probado todavía, porque necesitan tráfico real por los cables.

Las tres reglas cubren los tres ejemplos del enunciado: escaneo de puertos (20 SYN en 5 s desde un mismo origen), múltiples intentos de conexión (5 SYN a SSH en 30 s) y una firma definida (la cadena `prueba-ids` en una URL). Suricata corre en FW porque por ahí pasa todo el tráfico entre zonas.

### 7.5 Wireshark y punto de captura

- **Captura en el firewall:** `tcpdump -ni enx00e04c3604ff -w /tmp/dmz.pcap` en FW; el archivo se copia a un cliente con Wireshark (`scp`). FW es un punto de captura válido porque el tráfico lo atraviesa.
- **Tráfico que cruza el switch:** `span0` es el puerto espejo (SPAN) de SW1 y recibe una copia de todo el tráfico del switch (sección 3.1). Wireshark captura en `span0` desde el anfitrión de SW1. El modo promiscuo solo no bastaría: un switch no entrega a un puerto las tramas de otros equipos.

Captura sugerida para la entrega: el saludo de WireGuard (UDP 51820) en `enp3s0` de FW, o una solicitud HTTP a WEB01 con las etiquetas 802.1Q visibles en el SPAN.

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
| B: VPN | Peers remote-admin1 y remote-user1 acceden a las VLAN | WireGuard, DNAT de R-EDGE, políticas de FW |
| C: ngrok | Un usuario externo abre la URL pública | DMZ, salida controlada por FW y Multi-WAN |
| Monitoreo | Dashboard de Zabbix durante las pruebas | Métricas de ISP1 e ISP2 |

## 9. Diagnóstico rápido

| Síntoma | Qué revisar |
|---|---|
| Dos VM del mismo segmento no se ven | En el anfitrión: `bridge link` (cada tap en su bridge), MAC únicas, y `sysctl net.bridge.bridge-nf-call-iptables` en 0 si existe |
| R-EDGE sin salida por un ISP | Anclaje USB activo en el teléfono, su interfaz dentro del bridge (`bridge link` en el anfitrión) y que la red del teléfono no haya cambiado |
| Sin ping entre equipos de la misma VLAN | `ovs-vsctl show` en el anfitrión de SW1: cada tap con su `tag` correcto |
| Sin ping entre VLANs | `ip_forward` en R2 y `nft list ruleset` |
| VLAN sin Internet | Rutas de retorno en PROXY y FW; `ip route get 8.8.8.8` en cada salto |
| Web no carga pero el ping sí | `systemctl status squid`, `ip rule`, `ip route show table 100` y `rp_filter` en PROXY |
| Internet intermitente | `journalctl -t multiwan`; gateways reales en `mwan.conf` |
| VPN sin handshake | DNAT en R-EDGE, regla UDP 51820 en FW, `Endpoint` del cliente |
| VPN conecta pero no llega a las VLAN | Rutas a `10.200.x.x` en FW y `ip_forward` en VPN-SRV |
| Algo bloqueado sin saber dónde | `fw.log` en FW y `journalctl -k \| grep ACL-DENY` en R2 |

## 10. Pendientes de integración por encargado

Diferencias entre lo que cada encargado ha informado y lo que esta guía necesita para que los componentes funcionen juntos.

### Estudiante 1 (R2, SW1, Zabbix)

1. **Enlace hacia el proxy:** unir una interfaz física del anfitrión a `br-proxy-r2` y conectarla por cable a PROXY.
2. **Puerto espejo:** crear `span0` (sección 3.1) antes de las pruebas del estudiante 5.
3. **Zabbix:** restringir el frontend a la VLAN de Administración (sección 3.5).
4. **Sin redirección web:** R2 no debe redirigir el puerto 80; lo hace PROXY.
5. **DNS de los clientes:** el DHCP y PC-ADMIN01 deben usar `10.10.0.9` como servidor DNS (secciones 3.4 y 3.6).

### Estudiante 2 (PROXY)

1. **Desvío en PROXY:** quitar la petición de que R2 redirija el puerto 80 hacia `10.10.0.9:3129`; la regla va en el propio PROXY (sección 4.3).
2. **Alcance del desvío:** solo origen VLAN 10 y 20, y sin destinos internos (`10.10.0.0/16`).
3. **Reenvío:** activar `ip_forward`.
4. **HTTPS:** añadir el filtrado por SNI y la caché DNS de la sección 4.4, o preparar dominios de prueba que funcionen por HTTP. Sin el filtrado, dominios como facebook.com no se bloquean ni se registran; sin la caché, parte de las conexiones HTTPS permitidas falla.
5. **IP de origen:** usar TPROXY (sección 4.2), o avisar a los estudiantes 3 y 5 de que el tráfico web saldrá con la IP `10.10.0.6`.

### Estudiante 3 (R-EDGE)

1. **Redes de los teléfonos:** confirmar que los dos entregan redes distintas y anotarlas (sección 1.3).
2. **Enlace hacia el firewall:** R-EDGE es una VM, así que hay que unir una interfaz física del anfitrión a `br-edge-fw` y conectarla por cable a FW. Los teléfonos van en `br-isp1` y `br-isp2` (sección 1.3).
3. **VPN:** reenviar UDP 51820 hacia `10.10.50.2` (ya incluido en `mwan-apply.sh`).
4. **Cliente VPN de prueba:** alojar la VM PC-REMOTO en `br-isp1`, con un perfil de WireGuard del estudiante 4.

### Estudiante 4 (VPN y DMZ)

1. **`AllowedIPs` de los clientes:** incluir `10.10.0.0/16`, y `0.0.0.0/0` en al menos un peer para Full Tunnel. Con el valor actual, el cliente no llega a ninguna VLAN.
2. **Endpoint:** apuntar `vpn-multiwan` a la IP WAN de R-EDGE, y entregar un perfil de cliente al estudiante 3 para PC-REMOTO.
3. **Red del anfitrión y de VPN-SRV:** crear `br-dmz` con el Ethernet del cable hacia FW (sección 1.3) y conectar VPN-SRV a ese bridge con `10.10.50.2/28`, sin NAT.
4. **WEB01 y ngrok:** montar el servidor web, sus rutas hacia las redes VPN y el túnel (secciones 6.2 y 6.3).
5. **Pruebas:** añadir pruebas hacia las VLAN, no solo ping al servidor VPN.

### Estudiante 5 (FW)

1. **Configuración aplicada:** red, reglas, registros y Suricata ya están instalados en el equipo (sección 7 y carpeta `fw/`). Falta conectar los tres cables y repetir las pruebas con los equipos reales.
2. **Tráfico web del proxy:** si el estudiante 2 no usa TPROXY, añadir una regla que permita TCP 80 desde `10.10.0.6` hacia Internet.
3. **Puerto espejo:** coordinar con el estudiante 1 la captura en `span0`.
