# Firewall de XelajuNetwork (FW)

Documentación del firewall perimetral del proyecto: qué equipo es, qué archivos se configuraron, qué contiene cada uno y cómo se comprobó. Corresponde al componente del estudiante 5 (firewall, IDS y análisis de tráfico).

Todo lo que aparece aquí está **aplicado en el equipo real**. Los archivos de `sistema/` son copias idénticas de los instalados (se compararon byte a byte al crear esta carpeta).

## 1. Estado

| Aspecto | Estado |
|---|---|
| Red, rutas y reenvío | Aplicado |
| Reglas de nftables | Aplicadas y habilitadas al arranque |
| Registros de seguridad | Aplicados; permisos comprobados |
| Suricata (IDS) | Activo en las tres interfaces, con las tres reglas cargadas |
| Prueba de las reglas con vecinos simulados | 41 de 41 flujos correctos |
| Prueba con los equipos reales (cables conectados) | **Pendiente** |
| Alertas de Suricata con tráfico real | **Pendiente** |
| Comportamiento tras reiniciar el equipo | **Sin probar** |

## 2. El equipo

| Dato | Valor |
|---|---|
| Nombre | `firewall` |
| Sistema | Debian 13 (trixie) en modo texto, kernel 6.12 |
| Tipo | Equipo físico |
| Zona horaria | `America/Guatemala` |

Interfaces:

| Papel | Interfaz | Dirección | Conectada por cable a |
|---|---|---|---|
| WAN | `enp3s0` (integrada) | `10.10.0.2/30` | R-EDGE (`10.10.0.1`) |
| Interna | `enx00e04c360188` (USB-Ethernet) | `10.10.0.5/30` | PROXY (`10.10.0.6`) |
| DMZ | `enx00e04c3604ff` (USB-Ethernet) | `10.10.50.1/28` | VPN-SRV (`10.10.50.2`) y WEB01 (`10.10.50.10`) |
| Gestión | `wlp4s0` (Wi-Fi) | DHCP | No forma parte de la topología |

Paquetes instalados para este componente:

| Paquete | Versión | Uso |
|---|---|---|
| `nftables` | 1.1.3 | Firewall |
| `rsyslog` | 8.2504.0 | Registros en archivo |
| `suricata` | 7.0.10 | Detección de intrusiones |
| `tcpdump` | 4.99.5 | Capturas para Wireshark |
| `conntrack` | 1.4.8 | Consulta de la tabla de conexiones |

## 3. Árbol de archivos

Archivos configurados en el sistema:

```
/
├── etc/
│   ├── network/
│   │   └── interfaces              Direcciones, rutas estáticas y Wi-Fi de gestión
│   ├── nftables.conf               Reglas del firewall (denegación por defecto)
│   ├── sysctl.d/
│   │   └── 99-router.conf          Activa el reenvío de paquetes
│   ├── rsyslog.d/
│   │   └── 30-firewall.conf        Envía los registros del firewall a su archivo
│   ├── logrotate.d/
│   │   └── firewall                Rotación semanal del registro
│   └── suricata/
│       ├── suricata.yaml           Redes propias, interfaces y archivo de reglas (modificado)
│       └── rules/
│           └── local.rules         Las tres reglas de detección del proyecto
├── usr/local/sbin/
│   └── fw-rutas.sh                 Enrutamiento por política del tráfico reenviado
└── var/log/
    ├── firewall/
    │   └── fw.log                  Accesos permitidos y denegados (root:adm, 640)
    └── suricata/
        └── fast.log                Alertas del IDS
```

Esta carpeta del repositorio:

```
firewall_config/
├── README.md                       Este documento
├── sistema/                        Copia de los archivos, con la misma ruta que en el equipo
│   ├── etc/
│   │   ├── network/interfaces
│   │   ├── nftables.conf
│   │   ├── sysctl.d/99-router.conf
│   │   ├── rsyslog.d/30-firewall.conf
│   │   ├── logrotate.d/firewall
│   │   └── suricata/
│   │       ├── suricata.yaml.diff  Solo los cambios sobre el archivo original del paquete
│   │       └── rules/local.rules
│   └── usr/local/sbin/fw-rutas.sh
└── pruebas/
    ├── prueba-reglas.sh            Prueba las reglas con vecinos simulados
    └── prueba-sonda.py             Sonda TCP/UDP que usa el script anterior
```

Los archivos de registro no se copian al repositorio. De `suricata.yaml` solo se guarda la diferencia, porque el archivo completo tiene más de 2 000 líneas del paquete original.

Copias de los archivos originales, en el propio equipo: `/etc/network/interfaces.orig`, `/etc/nftables.conf.orig` y `/etc/suricata/suricata.yaml.orig`.

## 4. Red y enrutamiento

### 4.1 `/etc/sysctl.d/99-router.conf`

Activa el reenvío: sin él, el equipo descartaría todo paquete que no fuera para sí mismo.

```ini
net.ipv4.ip_forward = 1
```

### 4.2 `/etc/network/interfaces`

```
# FW (XelajuNetwork). Ver configuraciones.md, sección 7.1.

source /etc/network/interfaces.d/*

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

- **`allow-hotplug`:** la interfaz se configura cuando aparece. Hace falta para los adaptadores USB, que pueden no estar listos al inicio del arranque.
- **Rutas estáticas de la interfaz interna:** las cuatro VLAN y el enlace PROXY–R2 se alcanzan por PROXY (`10.10.0.6`). Son rutas específicas y no un resumen `/16`, para que una dirección `10.10.x.x` sin asignar no rebote entre equipos.
- **Rutas de la DMZ:** las dos redes VPN se alcanzan por VPN-SRV (`10.10.50.2`), que es quien descifra el túnel.
- **WAN sin `gateway`:** la salida hacia R-EDGE está en una tabla aparte (siguiente apartado).

### 4.3 `/usr/local/sbin/fw-rutas.sh`

El equipo conserva una Wi-Fi de gestión con Internet propia, y su ruta por defecto es la de esa Wi-Fi. El tráfico que el firewall **reenvía** no debe salir por ahí, sino por R-EDGE. Se resuelve con enrutamiento por política:

| Elemento | Contenido | Efecto |
|---|---|---|
| Tabla 100 | `default via 10.10.0.1 dev enp3s0` | Salida hacia R-EDGE |
| Regla 100 | Lo que entra por la interfaz interna o la DMZ consulta la tabla principal **sin** su ruta por defecto | Los destinos internos usan las rutas estáticas |
| Regla 101 | Si no hubo coincidencia, consulta la tabla 100 | Lo demás sale por R-EDGE |

```bash
#!/bin/bash
# FW: enrutamiento del tráfico reenviado.
# El tráfico que entra por la interfaz interna o por la DMZ usa primero la
# tabla principal sin su ruta por defecto (destinos internos) y, si no hay
# coincidencia, la tabla 100, cuya salida es R-EDGE. Así el tráfico propio del
# equipo puede seguir usando la Wi-Fi de gestión sin afectar al reenviado.
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

Cada interfaz lo ejecuta al levantarse; el script borra y vuelve a crear sus reglas, así que puede ejecutarse varias veces sin duplicarlas.

Comprobación:

```bash
ip rule                          # reglas 100 y 101 para las dos interfaces
ip route show table 100          # default via 10.10.0.1 dev enp3s0
ip route get 8.8.8.8 from 10.10.10.10 iif enx00e04c360188    # debe salir por enp3s0
ip route get 8.8.8.8                                          # el propio equipo: por wlp4s0
```

La Wi-Fi no reenvía tráfico de la red: ninguna regla del firewall la nombra, así que cualquier paquete que intentara cruzar por ella cae en la denegación por defecto. Si se retira la Wi-Fi, basta con añadir `gateway 10.10.0.1` a `enp3s0`.

## 5. Firewall: `/etc/nftables.conf`

```
#!/usr/sbin/nft -f
# FW (XelajuNetwork): firewall perimetral con denegación por defecto.
# Ver configuraciones.md, sección 7.2.
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

Cómo leerlo:

- **Denegación por defecto:** las cadenas `input` y `forward` tienen `policy drop`, y su última regla registra y descarta. Solo pasa lo que una regla permite de forma explícita.
- **Seguimiento de conexiones:** las reglas deciden sobre el primer paquete de cada conexión. El resto, incluidas las respuestas, pasa por `ct state established,related`. Por eso no hay reglas "de vuelta" y cada conexión genera una sola línea de registro.
- **Zonas por interfaz:** `$WAN`, `$INSIDE` y `$DMZ` son las tres interfaces. Cada regla indica por dónde entra y por dónde sale el tráfico, además de las direcciones.
- **Cadena `input`:** protege al propio firewall. Solo aceptan SSH y ping los administradores (VLAN ADMIN y VPN-ADMIN); los vecinos directos pueden hacer ping para comprobar los enlaces.
- **Sin duplicar las ACL internas:** no hay reglas entre VLANs. Ese tráfico lo decide R2 y nunca llega al firewall.
- **ngrok:** no hay regla de entrada desde Internet hacia la DMZ. El túnel lo abre WEB01 hacia fuera por el puerto 443, y las respuestas pasan por el seguimiento de conexiones.
- **VPN:** desde Internet solo entra UDP 51820 hacia VPN-SRV. Una vez descifrado, el tráfico vuelve al firewall con origen `10.200.10.x` o `10.200.20.x`, y ahí se aplica la política según el tipo de usuario.

Política que aplica (resumen de `direccionamiento.md`):

| Origen | Destino | Servicio | Acción |
|---|---|---|---|
| ADMIN, USERS, SERVERS | Internet | TCP 80, 443; DNS | Permitir |
| PROXY | Internet | DNS | Permitir |
| ADMIN | Internet | Ping | Permitir |
| ADMIN | DMZ | TCP 22, 80, 443; ping | Permitir |
| USERS | Servidores web de la DMZ | TCP 80, 443 | Permitir |
| DMZ | Redes internas | Todos | Denegar |
| Servidores web | Internet | TCP 443; DNS | Permitir |
| Internet | VPN-SRV | UDP 51820 | Permitir |
| Internet | DMZ y redes internas | Todos | Denegar |
| VPN-ADMIN | ADMIN, SERVERS, USERS | Todos | Permitir |
| VPN-ADMIN | Zabbix | TCP 80, 443 | Permitir |
| VPN-USERS | ADMIN | Todos | Denegar |
| VPN-USERS | SERVERS | TCP 80, 443 | Permitir |
| VPN-USERS | USERS | Todos | Permitir |
| VPN | Internet (full tunnel) | TCP 80, 443; DNS | Permitir |
| Zabbix ↔ R-EDGE | — | TCP 10050 y 10051; ping | Permitir |
| Cualquier otro | Cualquiera | Todos | Denegar y registrar |

Operación:

```bash
sudo nft -c -f /etc/nftables.conf     # valida sin aplicar
sudo systemctl restart nftables       # aplica
sudo nft list ruleset                 # muestra las reglas cargadas
```

## 6. Registros de seguridad

### 6.1 `/etc/rsyslog.d/30-firewall.conf`

```
# Registros del firewall: solo mensajes del kernel (nftables) con prefijo FW-.
if ($syslogfacility-text == "kern" and $msg contains "FW-") then {
    action(type="omfile" file="/var/log/firewall/fw.log" fileOwner="root" fileGroup="adm" fileCreateMode="0640")
    stop
}
```

Las reglas del firewall escriben en el registro del kernel con el prefijo `FW-ALLOW` o `FW-DENY`. Este filtro lleva esas líneas a `/var/log/firewall/fw.log` y evita que se mezclen con el resto. Exige que el mensaje venga del kernel para que ningún otro programa pueda escribir en el archivo de auditoría con solo mencionar "FW-".

Ejemplo de línea registrada (abreviada: se omiten la MAC y campos de la cabecera IP):

```
2026-10-04T21:06:06.707300-06:00 firewall kernel: FW-ALLOW IN=enx00e04c360188 OUT=enp3s0 SRC=10.10.10.10 DST=203.0.113.1 PROTO=TCP SPT=38177 DPT=80
```

| Dato pedido por el enunciado | Campo |
|---|---|
| Fecha y hora | Inicio de la línea |
| Acción | `FW-ALLOW` o `FW-DENY` |
| IP de origen | `SRC` |
| Destino | `DST` |
| Protocolo | `PROTO` |
| Puerto | `DPT` |

### 6.2 Permisos

| Ruta | Dueño | Modo |
|---|---|---|
| `/var/log/firewall/` | `root:adm` | `750` |
| `/var/log/firewall/fw.log` | `root:adm` | `640` |

Solo `root` y los miembros del grupo `adm` pueden leer el registro. Un administrador se añade con `sudo usermod -aG adm <usuario>`. Comprobado: el usuario común `firewall` recibe "Permission denied".

### 6.3 `/etc/logrotate.d/firewall`

```
/var/log/firewall/fw.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 0640 root adm
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
```

Consulta:

```bash
sudo tail -f /var/log/firewall/fw.log
sudo grep FW-DENY /var/log/firewall/fw.log | tail
```

## 7. Detección de intrusiones: Suricata

### 7.1 Cambios en `/etc/suricata/suricata.yaml`

Sobre el archivo original del paquete se cambiaron cuatro cosas: las redes propias (`HOME_NET`), las interfaces de captura (las tres del firewall), la carpeta de reglas y el archivo de reglas.

```diff
18c18
<     HOME_NET: "[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
---
>     HOME_NET: "[10.10.0.0/16,10.200.0.0/16]"
622c622,632
<   - interface: eth0
---
>   # FW: interfaz DMZ y interfaz interna (las dos primeras entradas, añadidas),
>   # e interfaz WAN (la entrada original, que conserva sus opciones).
>   - interface: enx00e04c3604ff
>     cluster-id: 97
>     cluster-type: cluster_flow
>     defrag: yes
>   - interface: enx00e04c360188
>     cluster-id: 98
>     cluster-type: cluster_flow
>     defrag: yes
>   - interface: enp3s0
2196c2206
< default-rule-path: /var/lib/suricata/rules
---
> default-rule-path: /etc/suricata/rules
2199c2209
<   - suricata.rules
---
>   - local.rules
```

### 7.2 `/etc/suricata/rules/local.rules`

```
alert tcp any any -> $HOME_NET any (msg:"XELAJU Posible escaneo de puertos"; flags:S; threshold:type threshold, track by_src, count 20, seconds 5; classtype:attempted-recon; sid:1000001; rev:1;)
alert tcp any any -> $HOME_NET 22 (msg:"XELAJU Multiples intentos de conexion SSH"; flags:S; threshold:type threshold, track by_src, count 5, seconds 30; classtype:attempted-admin; sid:1000002; rev:1;)
alert http any any -> any any (msg:"XELAJU Firma de prueba en URI"; flow:established,to_server; http.uri; content:"prueba-ids"; nocase; classtype:policy-violation; sid:1000003; rev:1;)
```

| sid | Detecta | Criterio |
|---|---|---|
| 1000001 | Escaneo de puertos | 20 intentos de conexión (SYN) en 5 segundos desde un mismo origen |
| 1000002 | Múltiples intentos de conexión a SSH | 5 intentos al puerto 22 en 30 segundos desde un mismo origen |
| 1000003 | Firma definida | La cadena `prueba-ids` en la dirección de una solicitud HTTP |

Suricata corre en el firewall porque por él pasa todo el tráfico entre zonas. Solo alerta; no bloquea.

Operación:

```bash
sudo suricata -T -c /etc/suricata/suricata.yaml    # prueba configuración y reglas
sudo systemctl restart suricata
sudo tail -f /var/log/suricata/fast.log            # alertas
```

## 8. Servicios

| Servicio | Al arranque | Función |
|---|---|---|
| `networking` | Habilitado | Interfaces, rutas y `fw-rutas.sh` |
| `nftables` | Habilitado | Carga `/etc/nftables.conf` |
| `rsyslog` | Habilitado | Escribe `fw.log` |
| `suricata` | Habilitado | IDS |

## 9. Pruebas realizadas

### 9.1 Reglas con vecinos simulados

`pruebas/prueba-reglas.sh` crea cuatro espacios de red aislados dentro del propio equipo: una copia del firewall con sus mismas interfaces, rutas y `nftables.conf`, y tres vecinos (R-EDGE con una dirección que hace de Internet, PROXY con un equipo de cada VLAN, y la DMZ con VPN-SRV, WEB01 y un peer de cada tipo de VPN). Después lanza 41 flujos y compara cada resultado con lo esperado.

```bash
sudo bash firewall_config/pruebas/prueba-reglas.sh
```

Resultado en el equipo: **41 correctas, 0 fallas**. No toca las interfaces reales ni las reglas en uso.

Qué cubre:

| Grupo | Flujos | Ejemplos |
|---|---|---|
| Redes internas → Internet | 9 | ADMIN por TCP 80 pasa; USERS por TCP 22 se bloquea |
| Redes internas → DMZ | 5 | ADMIN a WEB01 por SSH pasa; USERS a VPN-SRV se bloquea |
| DMZ → Internet y redes internas | 4 | WEB01 por TCP 443 pasa (ngrok); WEB01 a la VLAN ADMIN se bloquea |
| VPN-ADMIN | 4 | A la VLAN ADMIN pasa; a Zabbix por SSH se bloquea |
| VPN-USERS | 7 | A SERVERS por TCP 80 pasa; a la VLAN ADMIN se bloquea |
| Internet → red | 3 | UDP 51820 a VPN-SRV pasa; TCP 80 a WEB01 se bloquea |
| Monitoreo | 2 | Zabbix ↔ R-EDGE pasa |
| Acceso al propio firewall | 7 | Ping de ADMIN pasa; SSH desde Internet se bloquea |

También se comprobó en esa prueba que el tráfico reenviado sale por `enp3s0` (tabla 100) y que cada flujo deja su línea `FW-ALLOW` o `FW-DENY` en el registro.

### 9.2 Pendiente con los equipos reales

Al conectar los cables hay que repetir, con tráfico real, las pruebas de la fase 7 de `bitacora-pruebas.md` (FW-02 a FW-08, IDS-02 a IDS-04, CAP-01 y CAP-02), y antes las de enlace:

```bash
ping -c 3 10.10.0.1      # R-EDGE
ping -c 3 10.10.0.6      # PROXY
ping -c 3 10.10.50.2     # VPN-SRV
```

## 10. Diferencias con la guía general

Tres cosas se hicieron distinto a lo previsto en `configuraciones.md` antes de configurar el equipo, y la guía ya las recoge en su sección 7:

- **Wi-Fi de gestión y tabla 100:** la guía ponía la ruta por defecto hacia R-EDGE en la tabla principal. Aquí está en la tabla 100 para conservar la Wi-Fi.
- **Reglas añadidas en `input`:** se acepta el descubrimiento de vecinos IPv6 que necesita la Wi-Fi, y la difusión se descarta sin registrar para no llenar el registro de ruido.
- **Filtro de rsyslog:** se limitó a mensajes del kernel.

## 11. Cómo restaurar esta configuración

En un Debian 13 con las mismas tres interfaces:

```bash
sudo apt install nftables rsyslog suricata tcpdump conntrack
sudo timedatectl set-timezone America/Guatemala
sudo cp firewall_config/sistema/etc/network/interfaces /etc/network/interfaces
sudo cp firewall_config/sistema/etc/nftables.conf /etc/nftables.conf
sudo cp firewall_config/sistema/etc/sysctl.d/99-router.conf /etc/sysctl.d/
sudo cp firewall_config/sistema/etc/rsyslog.d/30-firewall.conf /etc/rsyslog.d/
sudo cp firewall_config/sistema/etc/logrotate.d/firewall /etc/logrotate.d/
sudo cp firewall_config/sistema/etc/suricata/rules/local.rules /etc/suricata/rules/
sudo install -m 755 firewall_config/sistema/usr/local/sbin/fw-rutas.sh /usr/local/sbin/
sudo patch /etc/suricata/suricata.yaml < firewall_config/sistema/etc/suricata/suricata.yaml.diff
sudo mkdir -p /var/log/firewall && sudo chown root:adm /var/log/firewall && sudo chmod 750 /var/log/firewall
sudo sysctl --system
sudo systemctl restart networking rsyslog
sudo systemctl enable --now nftables suricata
```

Si los nombres de las interfaces son otros, hay que cambiarlos en `interfaces`, en las tres definiciones iniciales de `nftables.conf`, en `fw-rutas.sh` y en el bloque `af-packet` de `suricata.yaml`. Esta secuencia no se ha ejecutado de principio a fin en un equipo limpio.
