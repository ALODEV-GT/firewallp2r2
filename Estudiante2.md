# CONTEXTO — Configuración de Squid / PROXY

## 1. Instalación y respaldo

Se instaló Squid y se realizó un respaldo de la configuración original.

```bash
sudo apt update
sudo apt install squid

sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
```

Versión instalada: Squid 7.7 en Debian sid/forky.

## 2. Topología del PROXY

Topología general:

```text
ISP1/ISP2
    ↓
  R-EDGE
    ↓
    FW
    ↓
  PROXY
    ↓
    R2
    ↓
 VLANs
```

Direcciones del PROXY:

```text
enp0s31f6
10.10.0.9/30
R2 → 10.10.0.10

enx9c69d3101d16
10.10.0.6/30
FW → 10.10.0.5
```

Perfiles de NetworkManager:

```text
squid-r2
squid-firewall
```

Configuración de los perfiles, creada previamente:

```bash
sudo nmcli connection add type ethernet \
  ifname enp0s31f6 \
  con-name squid-r2 \
  ipv4.method manual \
  ipv4.addresses 10.10.0.9/30 \
  ipv4.never-default yes \
  ipv6.method disabled

sudo nmcli connection add type ethernet \
  ifname enx9c69d3101d16 \
  con-name squid-firewall \
  ipv4.method manual \
  ipv4.addresses 10.10.0.6/30 \
  ipv4.never-default no \
  ipv6.method disabled
```

Gateway y rutas:

```bash
sudo nmcli connection modify squid-firewall \
  ipv4.gateway 10.10.0.5 \
  ipv4.route-metric 100

sudo nmcli connection modify squid-r2 \
  +ipv4.routes "10.10.10.0/27 10.10.0.10" \
  +ipv4.routes "10.10.20.0/25 10.10.0.10" \
  +ipv4.routes "10.10.30.0/28 10.10.0.10" \
  +ipv4.routes "10.10.40.0/27 10.10.0.10"
```

Redes alcanzables a través de R2:

```text
10.10.10.0/27 → VLAN 10 Admin
10.10.20.0/25 → VLAN 20 Users
10.10.30.0/28 → VLAN 30 Zabbix
10.10.40.0/27 → VLAN 40 Servers
```

El perfil `squid-r2` está configurado para no instalar una ruta predeterminada. El perfil `squid-firewall` tiene `ipv4.never-default no`, por lo que puede instalar una ruta predeterminada al activarse.

**Importante:** antes y después de activar los perfiles, revisar la ruta predeterminada. Cuando el equipo esté en casa, debe conservarse la salida por Wi-Fi y no deben activarse las interfaces del laboratorio si están desconectadas.

```bash
ip -4 route
ip -4 rule show
nmcli connection show --active
```

El perfil antiguo `Wired connection 1` fue configurado para no realizar autoconexión:

```bash
sudo nmcli connection modify "Wired connection 1" connection.autoconnect no
```

## 3. ACL de redes y listas de bloqueo

En `/etc/squid/squid.conf`:

```text
acl admins src 10.10.10.0/27
acl users src 10.10.20.0/25

acl admins_blocked dstdomain "/etc/squid/admins_blacklist"
acl users_blocked dstdomain "/etc/squid/users_blacklist"
```

Archivos:

```text
/etc/squid/admins_blacklist
/etc/squid/users_blacklist
```

Contenido actual.

`admins_blacklist`:

```text
.ilovepdf.com
.facebook.com
.instagram.com
.tiktok.com
.x.com
```

`users_blacklist`:

```text
.ilovepdf.com
.facebook.com
.instagram.com
.tiktok.com
.x.com
.youtube.com
.netflix.com
```

Las listas son independientes para permitir políticas diferentes entre Administración y Usuarios.

## 4. Reglas de acceso

En `/etc/squid/squid.conf`:

```text
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access deny to_localhost
http_access deny to_linklocal

http_access deny admins admins_blocked
http_access deny users users_blocked

http_access allow admins
http_access allow users

include /etc/squid/conf.d/*.conf
http_access deny all
```

Lógica:

* Administradores: bloquean los dominios de `admins_blacklist` y permiten los demás.
* Usuarios: bloquean los dominios de `users_blacklist` y permiten los demás.
* Cualquier otra red: denegada.

## 5. Validación de Squid

Validar la configuración antes de iniciar o reiniciar el servicio:

```bash
sudo squid -k parse
```

El parseo se ha validado sin errores.

Puede aparecer este warning de `/etc/squid/conf.d/debian.conf`:

```text
WARNING: refresh_pattern maximum age too high. Cropped back to 1 year.
```

Es un warning de la configuración incluida por Debian; no corresponde a las ACL del proyecto.

## 6. Puertos y configuración de TPROXY

Configuración relevante actual en `/etc/squid/squid.conf`:

```text
http_port 3128
http_port 3129 tproxy

tcp_outgoing_address 10.10.0.6
```

Significado:

* `3128`: proxy explícito convencional.
* `3129`: puerto para recibir tráfico HTTP interceptado mediante TPROXY.
* `tcp_outgoing_address 10.10.0.6`: establece la dirección de origen para las conexiones salientes de Squid.

**No cambiar `tproxy` por `intercept` sin revisar el diseño de red y las reglas de nftables.**

El diseño actual usa TPROXY para el tráfico HTTP seleccionado. No se ha configurado SSL Bump, interceptación HTTPS ni filtrado SNI.

Validar:

```bash
sudo squid -k parse
sudo ss -lntp | grep -E ':(3128|3129)\b'
```

## 7. Regla nftables para TPROXY

Se creó un archivo independiente:

```text
/etc/nftables-xelajunetwork.nft
```

Contenido actual:

```nft
table ip xelajunetwork_proxy {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname "enp0s31f6" ip saddr { 10.10.10.0/27, 10.10.20.0/25 } tcp dport 80 tproxy to :3129 meta mark set 0x1
    }
}
```

La regla selecciona:

```text
Interfaz de entrada: enp0s31f6
Orígenes: VLAN 10 y VLAN 20
Protocolo: TCP
Puerto de destino: 80
Acción: TPROXY hacia el puerto 3129
Marca: 0x1
```

La interfaz de entrada corresponde al enlace hacia R2 según la topología prevista. Debe comprobarse durante la integración que el tráfico de las VLAN realmente ingrese por esta interfaz.

La regla actual **no incluye una exclusión explícita para destinos internos**. Si se observa que intercepta solicitudes destinadas a recursos internos, revisar y corregir el criterio de destino antes de utilizarla en producción.

Validar sintaxis sin aplicar la tabla:

```bash
sudo nft -c -f /etc/nftables-xelajunetwork.nft
```

Consultar la tabla cuando esté activada:

```bash
sudo nft list table ip xelajunetwork_proxy
```

No cargar esta tabla manualmente cuando el equipo esté desconectado del laboratorio.

## 8. Enrutamiento por políticas y scripts de activación

Se crearon dos tablas de enrutamiento para el funcionamiento de TPROXY:

```text
Tabla 100 → xelajunetwork_tproxy
Tabla 101 → salida por el firewall
```

Se creó el directorio y se registró la tabla 100 en `/etc/iproute2/rt_tables`:

```bash
sudo install -d /etc/iproute2
```

Entrada correspondiente:

```text
100 xelajunetwork_tproxy
```

La tabla 100 utiliza una ruta local para que los paquetes marcados lleguen al socket TPROXY de Squid. La tabla 101 dirige las conexiones cuyo origen es `10.10.0.6` hacia el firewall `10.10.0.5`.

### Script de activación

Archivo:

```text
/usr/local/sbin/xelajunetwork-tproxy-on
```

Contenido actual:

```bash
#!/bin/bash
set -e

ip -4 addr show dev enp0s31f6 | grep -q '10\.10\.0\.9/30' || {
    echo "Error: enp0s31f6 no tiene 10.10.0.9/30"
    exit 1
}
ip -4 addr show dev enx9c69d3101d16 | grep -q '10\.10\.0\.6/30' || {
    echo "Error: la interfaz hacia el firewall no tiene 10.10.0.6/30"
    exit 1
}

ip route replace 10.10.0.4/30 dev enx9c69d3101d16 src 10.10.0.6 table 101
ip route replace default via 10.10.0.5 dev enx9c69d3101d16 table 101
ip rule show | grep -q 'from 10.10.0.6 lookup 101' ||
    ip rule add priority 1100 from 10.10.0.6/32 lookup 101

ip route replace local default dev lo table 100
ip rule show | grep -q 'fwmark 0x1 lookup xelajunetwork_tproxy' ||
    ip rule add priority 1000 fwmark 0x1 lookup xelajunetwork_tproxy

nft delete table ip xelajunetwork_proxy 2>/dev/null || true
nft -f /etc/nftables-xelajunetwork.nft
systemctl start squid

echo "TPROXY activado."
```

Permisos actuales: `root:root`, modo `750`.

### Script de desactivación

Archivo:

```text
/usr/local/sbin/xelajunetwork-tproxy-off
```

Contenido actual:

```bash
#!/bin/bash
set -e

nft delete table ip xelajunetwork_proxy 2>/dev/null || true
ip rule del priority 1000 fwmark 0x1 lookup xelajunetwork_tproxy 2>/dev/null || true
ip rule del priority 1100 from 10.10.0.6/32 lookup 101 2>/dev/null || true
ip route flush table 101 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
systemctl stop squid

echo "TPROXY desactivado."
```

Permisos actuales: `root:root`, modo `750`.

Validar sintaxis de ambos scripts:

```bash
sudo bash -n /usr/local/sbin/xelajunetwork-tproxy-on
sudo bash -n /usr/local/sbin/xelajunetwork-tproxy-off
```

### Activar TPROXY durante la integración

Solo cuando el equipo esté conectado físicamente a FW y R2 y las interfaces tengan las IP esperadas:

```bash
sudo /usr/local/sbin/xelajunetwork-tproxy-on
```

El script verifica las direcciones antes de modificar rutas y reglas. Si falla la comprobación, no continuar manualmente sin investigar el motivo.

### Desactivar TPROXY al terminar

```bash
sudo /usr/local/sbin/xelajunetwork-tproxy-off
```

Este script elimina la tabla nftables del proyecto, las reglas de política 1000 y 1100, limpia las tablas de rutas 100 y 101 y detiene Squid.

No modifica las reglas de Docker ni de Tailscale.

**Importante:** la activación y desactivación de TPROXY son temporales; no se ha configurado su activación automática mediante systemd.

## 9. Persistencia y seguridad de nftables

El archivo:

```text
/etc/nftables.conf
```

contiene una configuración base con:

```text
flush ruleset
```

El servicio `nftables` está habilitado y activo.

Por seguridad, **no modificar `/etc/nftables.conf` ni ejecutar `nft flush ruleset`**, ya que podría afectar reglas de Docker, Tailscale y otros servicios.

La configuración específica del proyecto está en:

```text
/etc/nftables-xelajunetwork.nft
```

Esta tabla solo se carga al ejecutar el script de activación. No debe agregarse a la configuración global de nftables sin revisar antes el impacto sobre el resto de las reglas.

Las reglas `ip rule` y las rutas de las tablas 100 y 101 también son temporales.

## 10. Consideración sobre Multi-WAN y rutas

Squid genera sus propias conexiones salientes. Con la configuración actual, esas conexiones usan `10.10.0.6` como dirección de origen y el script agrega una regla para consultarlas en la tabla 101, cuyo gateway es `10.10.0.5`.

Por tanto, las conexiones salientes de Squid no conservan automáticamente la IP original del cliente como dirección de origen.

Esto debe considerarse en las políticas de Multi-WAN y en los registros del firewall.

No se ha agregado NAT/MASQUERADE en el PROXY.

La regla TPROXY está destinada al tráfico HTTP TCP/80 seleccionado; no implica que HTTPS esté interceptado.

## 11. Configuración de logging

Formato configurado en `/etc/squid/squid.conf`:

```text
logformat project %ts.%03tu %>a %Ss/%03>Hs %<st %rm %ru
access_log /var/log/squid/access.log project
```

El registro incluye:

* Timestamp.
* IP de origen observada por Squid.
* Estado de Squid y código HTTP.
* Cantidad de bytes.
* Método HTTP.
* URL solicitada.

Archivo:

```text
/var/log/squid/access.log
```

El usuario `debian` pertenece al grupo `proxy`:

```bash
sudo usermod -aG proxy debian
```

Si se acaba de añadir al grupo, es necesario iniciar una sesión nueva para que el cambio de grupos se refleje en la sesión del usuario.

La rotación está gestionada por:

```text
/etc/logrotate.d/squid
```

Se configuró rotación diaria, compresión y conservación de dos rotaciones anteriores.

## 12. Validación del logging

Se probó el proxy explícito mediante:

```bash
curl -x http://127.0.0.1:3128 http://example.com/ -o /dev/null
```

La solicitud quedó registrada en:

```text
/var/log/squid/access.log
```

Esta prueba valida el funcionamiento local del proxy explícito y del logging. No valida por sí sola el funcionamiento de TPROXY ni las ACL aplicadas a clientes de las VLAN.

Comandos de revisión:

```bash
sudo tail -n 20 /var/log/squid/access.log
sudo tail -n 20 /var/log/squid/cache.log
```

## 13. Portal administrativo Flask

Se creó un portal web para visualizar información de:

```text
/var/log/squid/access.log
```

Ubicación:

```text
/run/media/debian/01DAB4F382BBCF90/Users/Santizo/Desktop/U 2026/8vo Semestre/Cursos/Redes 2/Proyectos/Proyecto 2/squid-portal
```

El proyecto utiliza un entorno virtual:

```text
.venv
```

El portal muestra:

* Número de solicitudes.
* Solicitudes permitidas.
* Solicitudes bloqueadas.
* Timestamp.
* IP de origen.
* Estado.
* Bytes.
* Método HTTP.
* URL.

Está configurado para escuchar en:

```text
0.0.0.0:8080
```

El acceso previsto para administración es:

```text
http://10.10.0.6:8080/
```

El acceso desde VLAN 10 depende de las rutas y reglas de firewall durante la integración.

## 14. Servicio systemd del portal

Archivo:

```text
/etc/systemd/system/squid-portal.service
```

Configuración relevante:

```text
User=debian
Group=debian
SupplementaryGroups=proxy
```

Esto permite que el portal lea el log de Squid.

El servicio está diseñado para ejecutarse manualmente durante las pruebas o demostraciones, sin inicio automático.

Consultar su configuración:

```bash
systemctl is-enabled squid-portal
systemctl status squid-portal --no-pager
```

Si no inicia, revisar el error antes de modificar el servicio:

```bash
sudo journalctl -u squid-portal -n 50 --no-pager
```

## 15. Inicio, verificación y apagado

### Antes de la integración

No activar TPROXY cuando las interfaces del laboratorio estén desconectadas. El estado de preparación es:

```text
Squid → detenido
TPROXY → desactivado
Portal → detenido
```

### Durante la integración

Activar las interfaces únicamente cuando estén conectadas físicamente:

```bash
sudo nmcli connection up squid-r2
sudo nmcli connection up squid-firewall
```

Revisar las direcciones y las rutas:

```bash
ip -br addr show enp0s31f6
ip -br addr show enx9c69d3101d16
ip -4 route
ip -4 rule show
```

Confirmar que la ruta predeterminada principal no haya cambiado inesperadamente. Después, comprobar la conectividad:

```bash
ping -c 4 10.10.0.5
ping -c 4 10.10.0.10
```

Si los enlaces o los pings fallan, detenerse y resolver la conectividad antes de activar TPROXY.

Activar Squid y TPROXY:

```bash
sudo /usr/local/sbin/xelajunetwork-tproxy-on
```

Iniciar el portal:

```bash
sudo systemctl start squid-portal
```

Verificar servicios y puertos:

```bash
systemctl status squid --no-pager
systemctl status squid-portal --no-pager

sudo ss -lntp | grep -E ':(3128|3129|8080)\b'
sudo squid -k parse
```

Verificar las reglas y rutas:

```bash
sudo nft list table ip xelajunetwork_proxy
ip -4 rule show
ip -4 route show table 100
ip -4 route show table 101
```

Verificar el portal:

```bash
curl -I http://127.0.0.1:8080/
curl -s http://127.0.0.1:8080/ | grep -E 'Solicitudes|Permitidas|Bloqueadas'
```

Revisar logs:

```bash
sudo tail -n 20 /var/log/squid/access.log
sudo tail -n 20 /var/log/squid/cache.log
```

### Al finalizar las pruebas

Detener el portal y desactivar TPROXY:

```bash
sudo systemctl stop squid-portal
sudo /usr/local/sbin/xelajunetwork-tproxy-off
```

Confirmar el estado:

```bash
systemctl is-active squid
systemctl is-active squid-portal
ip -4 rule show
```

Resultado esperado después de la desactivación:

```text
squid → inactive
squid-portal → inactive
```

Las reglas temporales del proyecto deben desaparecer. Las reglas preexistentes de Tailscale y Docker deben permanecer intactas.

## 16. Integración pendiente

Flujo esperado:

```text
ISP1/ISP2
    ↓
  R-EDGE
    ↓
    FW
    ↓
  PROXY
    ↓
    R2
    ↓
 VLAN 10 / VLAN 20 / VLAN 30 / VLAN 40
```

Durante la integración se debe verificar:

* Conectividad PROXY ↔ FW.
* Conectividad PROXY ↔ R2.
* Rutas hacia las VLAN.
* Conectividad extremo a extremo.
* Interceptación HTTP TCP/80 mediante TPROXY.
* Bloqueo mediante `admins_blacklist`.
* Bloqueo mediante `users_blacklist`.
* Registro de solicitudes en `access.log`.
* Acceso al portal desde VLAN 10.
* Funcionamiento de tráfico que no sea HTTP.
* Salida hacia Internet.
* Compatibilidad con las políticas de Multi-WAN.

Pruebas funcionales desde equipos de las VLAN:

```text
VLAN 10 → Admin
VLAN 20 → Users
```

Comprobar:

1. HTTP permitido.
2. HTTP bloqueado por blacklist.
3. Diferencias entre las políticas de Admin y Users.
4. Registro de IP, método, URL y resultado.
5. Tráfico no HTTP.
6. Acceso al portal desde Administración.
7. Conectividad hacia Internet.
8. Comportamiento conjunto con FW y Multi-WAN.

No se debe asumir que HTTPS será interceptado. No hay SSL Bump ni filtrado SNI configurado.

## 17. Estado actual y pendientes

### Configuración preparada

```text
Squid 7.7             → configurado
ACL Admin/Users       → configuradas
Blacklists            → configuradas
Puerto 3128           → proxy explícito
Puerto 3129           → TPROXY
tcp_outgoing_address  → 10.10.0.6
Logging               → configurado
Portal 8080           → configurado
NetworkManager        → perfiles configurados
Script TPROXY ON      → creado
Script TPROXY OFF     → creado
Tabla de rutas 100    → recreada al activar
Tabla de rutas 101    → recreada al activar
NAT/MASQUERADE        → no configurado
SSL Bump              → no configurado
Interceptación HTTPS  → no configurada
```

### Estado al terminar la preparación

```text
Squid                 → detenido
Squid-portal          → detenido
TPROXY                → desactivado
Tabla nftables del proyecto → no cargada
Reglas de política 1000/1100 → eliminadas
Rutas temporales 100/101     → limpiadas
Wi-Fi                  → debe conservar su ruta predeterminada
Docker/Tailscale       → no modificar
/etc/nftables.conf     → no modificar
```

Las interfaces del proyecto pueden estar desconectadas cuando el equipo no se encuentre en el laboratorio. En ese estado, no ejecutar el script de activación.

### Pendientes

```text
Conectar PROXY ↔ FW y PROXY ↔ R2
    ↓
Activar perfiles de NetworkManager
    ↓
Verificar direcciones, rutas y conectividad
    ↓
Activar TPROXY con el script
    ↓
Probar HTTP desde VLAN 10 y VLAN 20
    ↓
Verificar ACL y blacklists
    ↓
Verificar logs
    ↓
Probar el portal desde Administración
    ↓
Probar tráfico no HTTP
    ↓
Validar salida a Internet y Multi-WAN
    ↓
Desactivar TPROXY y detener el portal al finalizar
```

La configuración agregada para el proyecto debe poder activarse y desactivarse manualmente, sin alterar la configuración global de nftables ni las reglas de Docker/Tailscale.

**Nota para futuras IAs:** antes de cambiar archivos o rutas, revisar este contexto y el estado real del equipo. No asumir que la red del laboratorio está conectada, que Squid está activo ni que las reglas TPROXY están cargadas. Priorizar los scripts existentes para activar y desactivar TPROXY, y solicitar las salidas de diagnóstico antes de hacer cambios adicionales.
