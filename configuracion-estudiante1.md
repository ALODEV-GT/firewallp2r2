# Estudiante 1 — LAN, VLANs, R2, DHCP y Zabbix

Configuración actual del componente interno de XelajuNetwork, al 4 de octubre de 2026.
Basada en los requisitos de [Enunciado.pdf](Enunciado.pdf), el plan acordado en
[direccionamiento.md](direccionamiento.md), la propuesta de
[configuraciones.md](configuraciones.md) y la configuración instalada.

## 1. Responsabilidad

El Estudiante 1 administra SW1, las cuatro VLAN de la LAN, R2, los gateways,
el Inter-VLAN Routing, el DHCP restringido de Usuarios y las ACL internas.
También tiene a su cargo SRV01, el servidor Zabbix y el puerto SPAN para
capturar tráfico del switch.

El control perimetral corresponde al Estudiante 5. Este componente no
implementa proxy, Multi-WAN, VPN ni DMZ.

## 2. Topología

```text
PROXY (10.10.0.9/30, conectividad IP comprobada)
  |
  | enlace físico conectado: 10.10.0.8/30
  |
R2 (10.10.0.10/30)
  |
  | trunk 802.1Q: VLAN 10, 20, 30, 40
  |
SW1 — Open vSwitch en Ubuntu
  +-- VLAN 10 ADMIN   -- PC-ADMIN01
  +-- VLAN 20 USERS   -- PC-USER01, PC-USER02
  +-- VLAN 30 ZABBIX  -- ZABBIX
  +-- VLAN 40 SERVERS -- SRV01
```

SW1 es un switch de capa 2 ejecutado en el host Ubuntu, no una VM.
R2 y los cinco equipos de la LAN son VM Debian 13 administradas mediante
QEMU/KVM y libvirt.

El enlace físico hacia PROXY utiliza `enp0s31f6` del host, unido al bridge
`br-proxy-r2`, que no tiene IPv4. La primera NIC de R2 está conectada a ese
bridge; la segunda NIC está conectada al trunk de SW1.

El enlace R2 ↔ PROXY ya está conectado: R2 alcanza `10.10.0.9` y
PC-ADMIN01 alcanza tanto `10.10.0.9` como `10.10.0.6`, la interfaz de PROXY
hacia FW. La salida posterior a PROXY aún requiere diagnóstico grupal.

## 3. VLANs

| VLAN | Nombre | Red | Gateway |
|---|---|---|---|
| 10 | ADMIN | 10.10.10.0/27 | 10.10.10.1 |
| 20 | USERS | 10.10.20.0/25 | 10.10.20.1 |
| 30 | ZABBIX | 10.10.30.0/28 | 10.10.30.1 |
| 40 | SERVERS | 10.10.40.0/27 | 10.10.40.1 |

Los gateways pertenecen a las subinterfaces de R2. La asignación VLAN 30
para Zabbix y VLAN 40 para Servidores sigue el diseño grupal; los nombres
de segmentos del enunciado son ejemplos.

## 4. Direccionamiento

| Equipo/enlace | IPv4 | Asignación | Gateway / next-hop | DNS ADMIN/USERS |
|---|---|---|---|---|
| R2 hacia PROXY | 10.10.0.10/30 | Estática | 10.10.0.9 | — |
| PC-ADMIN01 | 10.10.10.10/27 | Estática | 10.10.10.1 | 10.10.0.9 |
| PC-USER01 | 10.10.20.10/25 | Reserva DHCP | 10.10.20.1 | 10.10.0.9 |
| PC-USER02 | 10.10.20.11/25 | Reserva DHCP | 10.10.20.1 | 10.10.0.9 |
| ZABBIX | 10.10.30.2/28 | Estática | 10.10.30.1 | — |
| SRV01 | 10.10.40.10/27 | Estática | 10.10.40.1 | — |

`10.10.0.9` es el DNS configurado para ADMIN y USERS. Aunque PC-ADMIN01
alcanza esa IP, la resolución de `example.com` termina en timeout tras
10 segundos: el servicio DNS esperado todavía no funciona desde ese
cliente. La LAN interna puede comunicarse mediante direcciones IP.

## 5. Interfaces reales

Los nombres instalados en R2 sustituyen los nombres de ejemplo `eth0/eth1`
de la propuesta grupal, sin cambiar el direccionamiento ni la topología.

| Interfaz de R2 | Función | IPv4 |
|---|---|---|
| enp1s0 | Enlace hacia PROXY mediante br-proxy-r2 | 10.10.0.10/30 |
| enp7s0 | Trunk hacia SW1, sin dirección IP | — |
| enp7s0.10 | Gateway VLAN 10 | 10.10.10.1/27 |
| enp7s0.20 | Gateway VLAN 20 y servicio DHCP | 10.10.20.1/25 |
| enp7s0.30 | Gateway VLAN 30 | 10.10.30.1/28 |
| enp7s0.40 | Gateway VLAN 40 | 10.10.40.1/27 |

PC-ADMIN01, PC-USER01, PC-USER02, SRV01 y ZABBIX utilizan `enp1s0` dentro
de sus respectivas VM. Son interfaces de acceso: los equipos no necesitan
crear subinterfaces VLAN.

## 6. SW1 — Open vSwitch

SW1 utiliza Open vSwitch 3.3.9 en Ubuntu. El bridge `sw1` no tiene dirección
IP y realiza únicamente conmutación de capa 2. Libvirt conecta las NIC
virtuales a OVS y conserva el modo de cada puerto en el XML de las VM.

| Puerto SW1 | Modo | VLAN | Equipo |
|---|---|---|---|
| tap-r2 | Trunk 802.1Q | 10, 20, 30, 40 | R2, enp7s0 |
| tap-admin01 | Access | 10 | PC-ADMIN01 |
| tap-user01 | Access | 20 | PC-USER01 |
| tap-user02 | Access | 20 | PC-USER02 |
| tap-zabbix | Access | 30 | ZABBIX |
| tap-srv01 | Access | 40 | SRV01 |
| span0 | Puerto interno de salida del espejo | — | Captura en el host |

Comprobación desde el host Ubuntu:

```bash
sudo ovs-vsctl show
ip -br addr show sw1
ip -br addr show span0
```

## 7. R2

R2 utiliza `enp1s0` para el enlace con PROXY y `enp7s0` como interfaz padre
de las cuatro subinterfaces 802.1Q. Cada subinterfaz tiene la dirección `.1`
de su red y funciona como gateway de la VLAN correspondiente.

El reenvío IPv4 está habilitado de forma persistente:
`net.ipv4.ip_forward = 1`. Las cuatro redes VLAN aparecen como rutas
directamente conectadas y R2 realiza el Inter-VLAN Routing sujeto a las ACL.

La ruta estática por defecto es:

```text
default via 10.10.0.9 dev enp1s0
```

R2 no realiza NAT ni redirige TCP 80/443 hacia Squid. Conserva las IP de
origen para que los componentes posteriores puedan aplicar sus políticas.
La intercepción del proxy corresponde a PROXY.

Comprobación dentro de R2:

```bash
ip -br addr
ip route
sysctl net.ipv4.ip_forward
```

## 8. DHCP restringido

El servicio tradicional `isc-dhcp-server` corre en R2 y escucha únicamente
en `enp7s0.20`. Solo la VLAN 20 utiliza DHCP; ADMIN, ZABBIX, SERVERS y el
router mantienen direccionamiento estático. No se utiliza Kea.

El registro de equipos autorizados está en `/etc/dhcp/usuarios.csv`, con
formato `Equipo,MAC,IP`. Las reservas utilizan las MAC reales de las VM:

| Equipo | MAC autorizada | IPv4 reservada |
|---|---|---|
| PC-USER01 | 52:54:00:67:62:0a | 10.10.20.10 |
| PC-USER02 | 52:54:00:5f:91:56 | 10.10.20.11 |

El servicio entrega máscara `255.255.255.128` (/25), gateway
`10.10.20.1` y DNS `10.10.0.9`. No existe un pool general ni una directiva
`range`; está aplicada la política `deny unknown-clients`.

Una MAC no registrada no recibe dirección por DHCP. La restricción controla
la asignación DHCP, no constituye por sí sola autenticación de acceso al
switch ni impide configurar una IP manualmente.

Las reservas activas se almacenan en `/etc/dhcp/reservas.conf`, incluido
por `/etc/dhcp/dhcpd.conf`. Cuando se modifica el registro, el mecanismo
local `/usr/local/sbin/dhcp-reservas.sh` genera y valida las reservas antes
de recargar el servicio.

## 9. ACL internas de R2

R2 aplica la matriz interna mediante nftables, en la tabla `inet acl` y
su cadena de reenvío, con denegación por defecto. La siguiente matriz
describe las conexiones nuevas; se permite el tráfico de retorno mediante
`established,related`.

| Origen | Destino | Servicio autorizado | Política |
|---|---|---|---|
| USERS | ADMIN | Ninguno | DENEGADO |
| USERS | ZABBIX (VLAN 30) | Ninguno | DENEGADO |
| USERS | SERVERS | TCP 80, 443 | PERMITIDO; resto DENEGADO |
| ADMIN | USERS | Todos | PERMITIDO |
| ADMIN | SERVERS | Todos | PERMITIDO |
| ADMIN | ZABBIX, 10.10.30.2 | TCP 22, 80, 443 | PERMITIDO |
| ADMIN | ZABBIX (VLAN 30) | ICMP echo-request | PERMITIDO |
| SERVERS | ADMIN / USERS | Ninguno | DENEGADO |
| SERVERS | ZABBIX, 10.10.30.2 | TCP 10051 | PERMITIDO |
| ZABBIX, 10.10.30.2 | SERVERS | TCP 10050, UDP 161, ICMP echo-request | PERMITIDO |
| Otras conexiones entre VLANs | Otras VLANs | No contempladas arriba | DENEGADO |

Las reglas también descartan estados inválidos y direcciones de origen
que no correspondan a la subred de la VLAN de entrada. Las denegaciones
se registran con el prefijo `ACL-DENY`, con limitación de frecuencia.

R2 controla solamente la comunicación entre VLANs. El tráfico reenviado
hacia o desde el enlace PROXY se deja pasar para que el firewall perimetral
del Estudiante 5 controle Internet, DMZ y VPN, sin duplicar responsabilidades.
Las ACL no filtran la comunicación directa entre equipos de una misma VLAN.

Comprobación dentro de R2:

```bash
sudo nft list ruleset
sudo journalctl -k | grep ACL-DENY
```

## 10. SRV01

SRV01 pertenece a VLAN 40 y utiliza `10.10.40.10/27`, con gateway
`10.10.40.1`.

| Servicio | Puerto | Uso |
|---|---|---|
| nginx HTTP | TCP 80 | Servicio web accesible desde USERS y ADMIN |
| nginx HTTPS | TCP 443 | Servicio web con certificado autofirmado de laboratorio |
| SSH | TCP 22 | Administración; USERS no puede acceder por la ACL de R2 |
| Zabbix Agent | TCP 10050 | Monitoreo desde 10.10.30.2 |

HTTP y HTTPS funcionan simultáneamente. El certificado HTTPS identifica
`10.10.40.10` y `srv01.xelaju.local`; al ser autofirmado, el navegador puede
mostrar una advertencia de confianza. Para comprobaciones de laboratorio
con curl puede utilizarse `-k`.

El agente tiene `Hostname=SRV01`, autoriza al servidor `10.10.30.2` y utiliza
esa misma dirección para checks activos hacia TCP 10051.

## 11. Zabbix

ZABBIX está en VLAN 30, con dirección `10.10.30.2/28` y gateway `10.10.30.1`.
Tiene instalados y activos Zabbix Server, MariaDB, Apache, el frontend Web
y Zabbix Agent.

Frontend:

```text
http://10.10.30.2/zabbix/
```

El acceso está permitido únicamente desde la VLAN ADMIN `10.10.10.0/27`.
Apache aplica la siguiente restricción en los bloques Directory y Location
del frontend:

```apache
Require ip 10.10.10.0/27
```

USERS está bloqueado tanto por las ACL de R2 como por la autorización del
frontend. El frontend está servido por HTTP 80; el permiso TCP 443 en la
ACL no implica que ZABBIX tenga HTTPS configurado.

SRV01 está siendo monitoreado con la plantilla **Linux by Zabbix agent**;
se recibe el indicador `agent.ping=1`. El cambio de la contraseña inicial
de la cuenta administrativa Web se realizará manualmente desde PC-ADMIN01.

El host `R-EDGE` está preparado con interfaz de agente esperada
`10.10.0.1:10050`, pero permanece deshabilitado. El dashboard de ISP1/ISP2
y las gráficas de tráfico de entrada/salida están creados y marcados
**PENDIENTE DE INTEGRACIÓN**. Las métricas de los ISP todavía no están
funcionando: falta integrar el equipo real y definir sus interfaces WAN.

## 12. SPAN / Port Mirroring

El espejo `span` de SW1 tiene `select_all=true` y utiliza `span0` como puerto
de salida. Copia el tráfico del switch hacia una interfaz de captura del
host Ubuntu; no depende únicamente del modo promiscuo.

Se comprobó la captura de tráfico entre VLANs. `span0` no tiene dirección
IP y puede utilizarse desde tcpdump o seleccionarse en Wireshark:

```bash
sudo tcpdump -i span0 -nn -e
```

## 13. Persistencia

La configuración operativa reside en el host y dentro de cada VM, sin
depender de archivos del repositorio para arrancar o funcionar.

| Equipo | Configuración persistente |
|---|---|
| Host Ubuntu | SW1/SPAN mediante `/etc/systemd/system/sw1-ovs.service`, que ejecuta `/usr/local/sbin/sw1-ovs.sh`; estado OVS en `/var/lib/openvswitch/conf.db`. Orden de arranque de libvirt y exclusión de interfaces OVS en las configuraciones locales de systemd y NetworkManager. |
| Libvirt | XML de las seis VM en `/etc/libvirt/qemu/`, con sus bridges, trunk y VLAN de acceso; autostart en `/etc/libvirt/qemu/autostart/`. |
| br-proxy-r2 | Bridge y asociación de `enp0s31f6` persistentes mediante Netplan en `/etc/netplan/`, con NetworkManager como renderer. |
| R2 | Red y VLANs en `/etc/network/interfaces`; forwarding en `/etc/sysctl.d/99-router.conf`; ACL en `/etc/nftables.conf`; DHCP en `/etc/default/isc-dhcp-server` y `/etc/dhcp/`. |
| SRV01 | Red estática local; HTTP/HTTPS en `/etc/nginx/`, incluido `/etc/nginx/conf.d/https-laboratorio.conf`; certificado local en `/etc/nginx/ssl/`; agente en `/etc/zabbix/zabbix_agentd.conf`. |
| ZABBIX | Red estática local; servidor, agente y frontend en `/etc/zabbix/`; restricción Web en `/etc/apache2/conf-available/zabbix-frontend-php.conf`, habilitada en Apache; datos MariaDB en `/var/lib/mysql/`. |
| PC-ADMIN01 / PC-USER01 | Perfil persistente NetworkManager en `/etc/NetworkManager/system-connections/`: ADMIN estático y USER01 por DHCP. |
| PC-USER02 | DHCP persistente mediante `/etc/network/interfaces` y configuración local de dhcpcd. |

Las seis VM tienen autostart configurado. Los servicios de red, DHCP,
nftables, nginx, Zabbix, Apache y MariaDB están habilitados en los equipos
que corresponden. La configuración de las VM fue validada tras reiniciarlas;
no se ha realizado una prueba de reinicio completo del host Ubuntu.

## 14. Estado actual

Los estados LISTO corresponden al componente local. No implican que se haya
validado el recorrido completo hacia los equipos de los demás integrantes.

| Componente | Estado |
|---|---|
| SW1 | LISTO |
| R2 | LISTO |
| VLANs | LISTO |
| DHCP restringido | LISTO |
| ACL internas | LISTO |
| SRV01 | LISTO |
| Zabbix local | LISTO |
| SPAN | LISTO |
| Enlace físico R2 ↔ PROXY | CONECTADO; conectividad IP comprobada |
| Acceso de PC-ADMIN01 a PROXY (.9 y .6) | COMPROBADO |
| DNS esperado en PROXY (10.10.0.9) | NO FUNCIONA desde PC-ADMIN01; resolución en timeout |
| Squid, filtrado Web y portal de PROXY | NO VALIDADOS |
| FW | PENDIENTE DIAGNÓSTICO / INTEGRACIÓN GRUPAL |
| R-EDGE | PENDIENTE DIAGNÓSTICO / INTEGRACIÓN GRUPAL |
| Métricas ISP1/ISP2 | PENDIENTE INTEGRACIÓN |
| Internet extremo a extremo | NO VALIDADO; pendiente de diagnóstico grupal |

## 15. Integración con compañeros

**Enlace hacia PROXY:** R2 utiliza `10.10.0.10/30` y PROXY `10.10.0.9/30`.
El enlace físico está conectado por `enp0s31f6` del host Ubuntu, integrada
en `br-proxy-r2`. R2 conserva su ruta por defecto hacia `10.10.0.9`.

Comprobaciones manuales de conectividad:

| Origen | Destino | Resultado de ping |
|---|---|---|
| R2 | PROXY 10.10.0.9 | 4/4 respuestas; 0% pérdida |
| PC-ADMIN01 | Gateway R2 10.10.10.1 | 4/4 respuestas; 0% pérdida |
| PC-ADMIN01 | PROXY 10.10.0.9 | 4/4 respuestas; 0% pérdida |
| PC-ADMIN01 | PROXY hacia FW, 10.10.0.6 | 4/4 respuestas; 0% pérdida |

**Salida y DNS:** desde PC-ADMIN01, el traceroute a `8.8.8.8` responde en
el salto 1 (`10.10.10.1`) y salto 2 (`10.10.0.9`); desde el salto 3 no hay
respuesta. El ping a `8.8.8.8` tiene 100% de pérdida y la consulta Web a
`http://example.com` falla por timeout de resolución tras 10 segundos,
usando DNS `10.10.0.9`. Internet extremo a extremo no está validado.
Estos resultados no identifican por sí solos la causa: la salida posterior
a PROXY/FW/R-EDGE y el DNS requieren diagnóstico grupal. No se ha validado
el funcionamiento de Squid, el filtrado Web ni el portal.

PROXY necesita rutas de retorno a `10.10.10.0/27`, `10.10.20.0/25`,
`10.10.30.0/28` y `10.10.40.0/27` mediante `10.10.0.10`, según el plan grupal.
La conectividad comprobada desde ADMIN no valida aún las rutas de retorno
de todas las VLAN. Los clientes ADMIN y USERS utilizan DNS `10.10.0.9`;
queda pendiente resolver el timeout y comprobar el servicio desde ellos.

**Monitoreo con el Estudiante 3:** Zabbix espera métricas de R-EDGE para
tráfico de entrada y salida de ISP1 e ISP2. Deben confirmarse los nombres
reales de sus interfaces WAN y completar las macros `{$ISP1_IF}` y
`{$ISP2_IF}` del host preparado. La integración prevista utiliza el agente
en `10.10.0.1:10050`; si se coordinan checks activos, el servidor receptor
es `10.10.30.2:10051`. El host debe habilitarse después de comprobar la
conectividad y la recepción real de métricas.

**Seguridad interna:** las ACL entre VLANs ya están implementadas en R2.
El Estudiante 5 conserva la responsabilidad del filtrado perimetral y de
las autorizaciones necesarias para alcanzar Zabbix desde R-EDGE. No es
necesario duplicar en FW la matriz interna de R2.
