# CONTEXTO — Configuración de Squid / PROXY

## 1. Instalación y respaldo

Se instaló Squid y se realizó un respaldo de la configuración original.

```bash
sudo apt update
sudo apt install squid

sudo cp /etc/squid/squid.conf /etc/squid/squid.conf.backup
```

Versión instalada: Squid 7.7 en Debian sid/forky.

---

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
10.10.0.6/30
FW → 10.10.0.5

enx9c69d3101d16
10.10.0.9/30
R2 → 10.10.0.10
```

Perfiles de NetworkManager:

```text
squid-firewall
squid-r2
```

Configuración:

```bash
sudo nmcli connection add type ethernet \
  ifname enp0s31f6 \
  con-name squid-firewall \
  ipv4.method manual \
  ipv4.addresses 10.10.0.6/30 \
  ipv4.never-default no \
  ipv6.method disabled

sudo nmcli connection add type ethernet \
  ifname enx9c69d3101d16 \
  con-name squid-r2 \
  ipv4.method manual \
  ipv4.addresses 10.10.0.9/30 \
  ipv4.never-default yes \
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

Las interfaces del proyecto se mantienen desconectadas mientras no exista conexión física con FW y R2. Esto evita modificar la salida a Internet del equipo durante el desarrollo.

El perfil antiguo `Wired connection 1` fue configurado para no realizar autoconexión:

```bash
sudo nmcli connection modify "Wired connection 1" connection.autoconnect no
```

---

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

Contenido actual:

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

---

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

La lógica es:

* Administradores: bloquean los dominios de `admins_blacklist` y permiten los demás.
* Usuarios: bloquean los dominios de `users_blacklist` y permiten los demás.
* Cualquier otra red: denegada.

---

## 5. Validación de Squid

La configuración fue validada mediante:

```bash
sudo squid -k parse
```

El parseo termina sin errores.

El siguiente warning pertenece a `/etc/squid/conf.d/debian.conf`:

```text
WARNING: refresh_pattern maximum age too high. Cropped back to 1 year.
```

No corresponde a la configuración del proyecto y no impide el funcionamiento de Squid.

---

## 6. Configuración de proxy e intercept

Squid utiliza:

```text
3128 → proxy explícito
3129 → proxy HTTP en modo intercept
```

Configuración:

```text
http_port 3128
http_port 3129 intercept
```

* `3128` → proxy convencional.
* `3129` → recibe tráfico HTTP redirigido localmente en el PROXY.

El diseño corregido establece que **R2 no debe realizar el redirect**. R2 solamente enruta el tráfico hacia el PROXY.

La redirección TCP/80 se realiza mediante `nftables` en el PROXY, antes de que el tráfico llegue a Squid.

No se configuró:

* SSL Bump.
* Interceptación HTTPS.
* Filtrado SNI.
* TPROXY.

La asignación solamente requiere interceptación HTTP.

---

## 7. Redirección HTTP y forwarding del PROXY

Se habilitó temporalmente el forwarding IPv4:

```bash
sudo /usr/sbin/sysctl -w net.ipv4.ip_forward=1
```

La configuración actual está aplicada en memoria y no se agregó a `/etc/sysctl.conf` ni a `/etc/sysctl.d/`.

Se creó una tabla independiente de nftables:

```text
xelajunetwork_proxy
```

Actualmente contiene:

```text
VLAN 10/20
    ↓
   R2
    ↓
  PROXY
    ├── TCP/80 externo → Squid :3129
    └── resto → FW
```

Regla de interceptación:

```text
Interfaz de entrada:
enx9c69d3101d16

Origen:
10.10.10.0/27
10.10.20.0/25

Protocolo:
TCP

Puerto:
80

Destino excluido:
10.10.0.0/16

Redirección:
3129
```

La exclusión de `10.10.0.0/16` evita interceptar tráfico dirigido a las redes internas del proyecto.

La cadena de forwarding del proyecto utiliza `policy accept` y prioridad `-50`. Esto permite que el tráfico entre las interfaces de R2 y FW sea procesado por el PROXY antes de las reglas `FORWARD` administradas por Docker.

El flujo esperado es:

```text
R2 → PROXY → FW
FW → PROXY → R2
```

Las reglas existentes de Docker y Tailscale no fueron modificadas. La tabla `xelajunetwork_proxy` utiliza cadenas independientes para evitar interferir con las reglas administradas por estos servicios.

La cadena `FORWARD` administrada por Docker mantiene su propia política `drop`; la configuración del proyecto no reemplaza ni modifica dicha cadena.

No se agregó NAT/MASQUERADE en el PROXY.


---

## 8. Persistencia y reversibilidad de la configuración de red

El archivo:

```text
/etc/nftables.conf
```

actualmente contiene una configuración base con:

```text
flush ruleset
```

y el servicio `nftables` está habilitado y activo.

Por seguridad, **no se modificó `/etc/nftables.conf`**.

La tabla:

```text
xelajunetwork_proxy
```

se encuentra actualmente cargada en memoria mediante:

```text
/tmp/xelajunetwork-proxy.nft
```

La configuración de forwarding también es temporal.

Esto permite revertir posteriormente la configuración del proyecto sin modificar las reglas permanentes de Docker/Tailscale.

Para la reversión posterior a la calificación se deberá:

1. Eliminar la tabla `xelajunetwork_proxy`.
2. Restaurar el valor anterior de `net.ipv4.ip_forward`.
3. Mantener intactos Docker, Tailscale y `/etc/nftables.conf`.

---

## 9. Consideración sobre Multi-WAN

El tráfico HTTP interceptado por Squid sale posteriormente hacia el FW utilizando como origen la dirección del PROXY:

```text
10.10.0.6
```

Por tanto, el tráfico que originalmente provenía de:

```text
10.10.10.x
10.10.20.x
```

no conserva necesariamente esa IP como origen en la conexión saliente generada por Squid.

No se implementó TPROXY para conservar la IP original, ya que no es requerido por el alcance actual.

Esto debe ser considerado por la configuración de Multi-WAN del grupo.

---

## 10. Configuración de logging

Se utiliza un formato específico para el proyecto:

```text
logformat project %ts.%03tu %>a %Ss/%03>Hs %<st %rm %ru
access_log /var/log/squid/access.log project
```

El registro incluye:

* Timestamp.
* IP de origen.
* Estado de Squid.
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

Esto permite al portal leer el log.

La rotación está gestionada por:

```text
/etc/logrotate.d/squid
```

Se realiza rotación diaria, compresión y conservación de dos rotaciones anteriores.

---

## 11. Validación del logging

Se probó el proxy explícito mediante:

```bash
curl -x http://127.0.0.1:3128 http://example.com/ -o /dev/null
```

La solicitud quedó registrada en:

```text
/var/log/squid/access.log
```

Esta prueba valida el funcionamiento local de Squid y del logging.

Las pruebas reales de las ACL de Administradores y Usuarios se realizarán durante la integración con las VLANs.

---

## 12. Portal administrativo Flask

Se creó un portal web para visualizar información de:

```text
/var/log/squid/access.log
```

Ubicación:

```text
/run/media/debian/01DAB4F382BBCF90/Users/Santizo/Desktop/U 2026/8vo Semestre/Cursos/Redes 2/Proyectos/Proyecto 2/squid-portal
```

El proyecto utiliza:

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

Actualmente escucha en:

```text
0.0.0.0:8080
```

El acceso previsto para la administración es desde VLAN 10 mediante la IP del PROXY:

```text
10.10.0.6:8080
```

El acceso efectivo desde VLAN 10 queda sujeto a las rutas y reglas de firewall definidas durante la integración con el resto de la infraestructura.

El comportamiento de acceso desde otras redes se validará durante la integración con FW y R2.


---

## 13. Servicio systemd del portal

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

Esto permite que el portal lea:

```text
/var/log/squid/access.log
```

El servicio no está habilitado para iniciar automáticamente:

```bash
systemctl is-enabled squid-portal
```

Resultado esperado:

```text
disabled
```

El servicio se ejecuta únicamente durante las pruebas o demostraciones.

---

## 14. Inicio y apagado temporal

Los servicios permanecen deshabilitados al arranque.

Para una demostración:

```bash
sudo systemctl start squid
sudo systemctl start squid-portal
```

Verificación:

```bash
sudo systemctl status squid --no-pager
sudo systemctl status squid-portal --no-pager
```

Al finalizar:

```bash
sudo systemctl stop squid-portal
sudo systemctl stop squid
```

Estado esperado:

```text
squid        → disabled
squid-portal → disabled
```

---

## 15. Integración pendiente

La configuración del PROXY está preparada para conectarse con FW y R2.

Flujo:

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
* Rutas hacia las VLANs.
* Conectividad extremo a extremo.
* Redirección HTTP realizada por el PROXY.
* Bloqueo mediante `admins_blacklist`.
* Bloqueo mediante `users_blacklist`.
* Registro de solicitudes en `access.log`.
* Acceso al portal desde VLAN 10.
* Funcionamiento de tráfico no HTTP.
* Salida hacia Internet.
* Compatibilidad con las políticas de Multi-WAN.

---

## 16. Pruebas de integración

Cuando FW y R2 estén físicamente conectados, primero se activarán temporalmente las interfaces:

```bash
sudo nmcli connection up squid-firewall
sudo nmcli connection up squid-r2
```

Verificar interfaces:

```bash
ip -br addr show
```

Verificar rutas:

```bash
ip route
```

Conectividad con FW y R2:

```bash
ping -c 4 10.10.0.5
ping -c 4 10.10.0.10
```

Iniciar servicios:

```bash
sudo systemctl start squid
sudo systemctl start squid-portal
```

Verificar puertos:

```bash
sudo ss -lntp | grep -E ':(3128|3129|8080)\b'
```

Validar Squid:

```bash
sudo squid -k parse
```

Revisar logs:

```bash
sudo tail -n 20 /var/log/squid/access.log
sudo tail -n 20 /var/log/squid/cache.log
```

La validación funcional se realizará desde equipos de las VLANs:

```text
VLAN 10 → Admin
VLAN 20 → Users
```

Las pruebas deberán comprobar:

1. HTTP permitido.
2. HTTP bloqueado por blacklist.
3. Diferencias entre las políticas de Admin y Users.
4. Registro de IP, método, URL y resultado.
5. Tráfico no HTTP sin pasar por Squid.
6. Acceso al portal desde Administración.
7. Conectividad hacia Internet.
8. Comportamiento conjunto con FW y Multi-WAN.

El tráfico HTTPS no será interceptado mediante SSL Bump.

---

## 17. Estado actual

Configuración preparada antes de la integración física:

```text
Squid                  → configurado
ACL Admin/Users        → configuradas
Blacklists             → configuradas
3128                   → proxy explícito
3129                   → HTTP intercept
Logging                → configurado
Portal 8080            → configurado
NetworkManager         → configurado
ip_forward             → habilitado temporalmente
nftables redirect      → configurado temporalmente
nftables forwarding    → configurado temporalmente
NAT en PROXY           → no utilizado
TPROXY                 → no utilizado
SSL Bump               → no utilizado
```

Pendiente después de conectar con el equipo:

```text
PROXY ↔ FW
PROXY ↔ R2
    ↓
Pruebas de conectividad
    ↓
Pruebas de routing
    ↓
Pruebas de interceptación HTTP
    ↓
Pruebas de ACL/blacklist
    ↓
Pruebas de logging
    ↓
Prueba del portal
    ↓
Pruebas de tráfico no HTTP
    ↓
Validación con Multi-WAN/FW
```

La configuración de red agregada para el proyecto es temporal y deberá poder revertirse después de la calificación.
