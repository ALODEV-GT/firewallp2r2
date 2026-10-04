# XelajuNetwork: plan de direccionamiento, rutas y seguridad

Cadena principal: ISP1/ISP2 → R-EDGE → FW → PROXY → R2 → VLANs. La DMZ (servidores web y servidor WireGuard) cuelga del firewall.

## Supuestos por confirmar

- **WAN:** los dos ISP son dos teléfonos celulares conectados por USB. Sus IPs son marcadores; dependen de la red que entregue cada teléfono, y las dos redes deben ser distintas (ver `configuraciones.md`, sección 1.3).
- **DMZ y VPN en un mismo segmento:** WireGuard y los servidores web comparten `10.10.50.0/28` en una sola interfaz del firewall. Separarlos exigiría una cuarta interfaz en FW.
- **DHCP en R2:** el servicio DHCP restringido corre en R2 y escucha solo en `eth1.20`. El diagrama del enunciado lo dibuja dentro de la VLAN de Usuarios; si se exige un equipo aparte, puede moverse a una VM en esa VLAN con los mismos archivos.
- **Puertos elegidos:** 51820 para WireGuard y 8080 para el portal de Squid.
- **VPN-ADMIN hacia Zabbix:** el enunciado restringe el dashboard a la VLAN de Administración; quitar esa regla si se interpreta de forma estricta.

## Resumen de redes

| Red | Máscara | Uso |
|---|---|---|
| 10.10.0.0/30 | 255.255.255.252 | Enlace R-EDGE – FW |
| 10.10.0.4/30 | 255.255.255.252 | Enlace FW – PROXY |
| 10.10.0.8/30 | 255.255.255.252 | Enlace PROXY – R2 |
| 10.10.10.0/27 | 255.255.255.224 | VLAN 10 – Administración |
| 10.10.20.0/25 | 255.255.255.128 | VLAN 20 – Usuarios (DHCP restringido) |
| 10.10.30.0/28 | 255.255.255.240 | VLAN 30 – Zabbix |
| 10.10.40.0/27 | 255.255.255.224 | VLAN 40 – Servidores |
| 10.10.50.0/28 | 255.255.255.240 | DMZ (WEB01, WEB02, VPN-SRV) |
| 10.200.10.0/24 | 255.255.255.0 | VPN-ADMIN |
| 10.200.20.0/24 | 255.255.255.0 | VPN-USERS |

## Interfaces físicas

| Dispositivo | Físicas | Uso |
|---|---|---|
| R-EDGE | 3 | ISP1 (teléfono 1), ISP2 (teléfono 2), hacia FW |
| FW | 3 | hacia R-EDGE, hacia PROXY, DMZ |
| PROXY | 2 | hacia FW, hacia R2 |
| R2 | 2 | hacia PROXY, troncal 802.1Q (4 subinterfaces) |
| SW1 | 8 | troncal hacia R2, 6 puertos de acceso, 1 puerto espejo (SPAN) |
| VPN-SRV | 1 | DMZ (más `wg0`, virtual) |
| WEB01 / WEB02 | 1 | DMZ |
| Zabbix, SRV01, PCs | 1 | su VLAN |

## Tabla de direccionamiento

| Dispositivo | Interfaz | IP | Máscara | Gateway | Red |
|---|---|---|---|---|---|
| R-EDGE | eth0 (ISP1) | 192.168.41.2 * | 255.255.255.0 | 192.168.41.1 * | 192.168.41.0/24 * |
| R-EDGE | eth1 (ISP2) | 192.168.42.2 * | 255.255.255.0 | 192.168.42.1 * | 192.168.42.0/24 * |
| R-EDGE | eth2 | 10.10.0.1 | 255.255.255.252 | — | 10.10.0.0/30 |
| FW | eth0 | 10.10.0.2 | 255.255.255.252 | 10.10.0.1 | 10.10.0.0/30 |
| FW | eth1 | 10.10.0.5 | 255.255.255.252 | — | 10.10.0.4/30 |
| FW | eth2 (DMZ) | 10.10.50.1 | 255.255.255.240 | — | 10.10.50.0/28 |
| PROXY | eth0 | 10.10.0.6 | 255.255.255.252 | 10.10.0.5 | 10.10.0.4/30 |
| PROXY | eth1 | 10.10.0.9 | 255.255.255.252 | — | 10.10.0.8/30 |
| R2 | eth0 | 10.10.0.10 | 255.255.255.252 | 10.10.0.9 | 10.10.0.8/30 |
| R2 | eth1.10 | 10.10.10.1 | 255.255.255.224 | — | 10.10.10.0/27 |
| R2 | eth1.20 (gateway y DHCP) | 10.10.20.1 | 255.255.255.128 | — | 10.10.20.0/25 |
| R2 | eth1.30 | 10.10.30.1 | 255.255.255.240 | — | 10.10.30.0/28 |
| R2 | eth1.40 | 10.10.40.1 | 255.255.255.224 | — | 10.10.40.0/27 |
| VPN-SRV | eth0 | 10.10.50.2 | 255.255.255.240 | 10.10.50.1 | 10.10.50.0/28 |
| VPN-SRV | wg0 | 10.200.10.1 | 255.255.255.0 | — | 10.200.10.0/24 |
| VPN-SRV | wg0 | 10.200.20.1 | 255.255.255.0 | — | 10.200.20.0/24 |
| WEB01 | eth0 | 10.10.50.10 | 255.255.255.240 | 10.10.50.1 | 10.10.50.0/28 |
| WEB02 (opcional) | eth0 | 10.10.50.11 | 255.255.255.240 | 10.10.50.1 | 10.10.50.0/28 |
| PC-ADMIN01 | eth0 | 10.10.10.10 | 255.255.255.224 | 10.10.10.1 | 10.10.10.0/27 |
| PC-USER01 (DHCP) | eth0 | 10.10.20.10 | 255.255.255.128 | 10.10.20.1 | 10.10.20.0/25 |
| PC-USER02 (DHCP) | eth0 | 10.10.20.11 | 255.255.255.128 | 10.10.20.1 | 10.10.20.0/25 |
| ZABBIX | eth0 | 10.10.30.2 | 255.255.255.240 | 10.10.30.1 | 10.10.30.0/28 |
| SRV01 | eth0 | 10.10.40.10 | 255.255.255.224 | 10.10.40.1 | 10.10.40.0/27 |
| Peer Admin 1 | wg0 | 10.200.10.10 | 255.255.255.0 | túnel | 10.200.10.0/24 |
| Peer Admin 2 | wg0 | 10.200.10.11 | 255.255.255.0 | túnel | 10.200.10.0/24 |
| Peer User 1 | wg0 | 10.200.20.10 | 255.255.255.0 | túnel | 10.200.20.0/24 |
| Peer User 2 | wg0 | 10.200.20.11 | 255.255.255.0 | túnel | 10.200.20.0/24 |
| Peer User 3 | wg0 | 10.200.20.12 | 255.255.255.0 | túnel | 10.200.20.0/24 |

\* Marcador: sustituir por la red real que entregue cada teléfono.

SW1 es de capa 2 y no lleva IP. Sus puertos:

| Puerto | Modo | VLAN | Conectado a |
|---|---|---|---|
| eth0 | Troncal 802.1Q | 10, 20, 30, 40 | R2 eth1 |
| eth1 | Acceso | 10 | PC-ADMIN01 |
| eth2 | Acceso | 20 | Libre: cliente no registrado (prueba de DHCP) |
| eth3 | Acceso | 20 | PC-USER01 |
| eth4 | Acceso | 20 | PC-USER02 |
| eth5 | Acceso | 30 | ZABBIX |
| eth6 | Acceso | 40 | SRV01 |
| eth7 | Espejo (SPAN) | — | Captura con Wireshark |

## Tabla de rutas

Solo rutas estáticas; las redes conectadas directamente no se listan.

| Dispositivo | Red destino | Máscara | Next Hop | Interfaz |
|---|---|---|---|---|
| R-EDGE | 0.0.0.0 | 0.0.0.0 | 192.168.41.1 * | eth0 |
| R-EDGE | 0.0.0.0 | 0.0.0.0 | 192.168.42.1 * | eth1 |
| R-EDGE | 10.10.0.0 | 255.255.0.0 | 10.10.0.2 | eth2 |
| R-EDGE | 10.200.10.0 | 255.255.255.0 | 10.10.0.2 | eth2 |
| R-EDGE | 10.200.20.0 | 255.255.255.0 | 10.10.0.2 | eth2 |
| FW | 0.0.0.0 | 0.0.0.0 | 10.10.0.1 | eth0 |
| FW | 10.10.0.8 | 255.255.255.252 | 10.10.0.6 | eth1 |
| FW | 10.10.10.0 | 255.255.255.224 | 10.10.0.6 | eth1 |
| FW | 10.10.20.0 | 255.255.255.128 | 10.10.0.6 | eth1 |
| FW | 10.10.30.0 | 255.255.255.240 | 10.10.0.6 | eth1 |
| FW | 10.10.40.0 | 255.255.255.224 | 10.10.0.6 | eth1 |
| FW | 10.200.10.0 | 255.255.255.0 | 10.10.50.2 | eth2 |
| FW | 10.200.20.0 | 255.255.255.0 | 10.10.50.2 | eth2 |
| PROXY | 0.0.0.0 | 0.0.0.0 | 10.10.0.5 | eth0 |
| PROXY | 10.10.10.0 | 255.255.255.224 | 10.10.0.10 | eth1 |
| PROXY | 10.10.20.0 | 255.255.255.128 | 10.10.0.10 | eth1 |
| PROXY | 10.10.30.0 | 255.255.255.240 | 10.10.0.10 | eth1 |
| PROXY | 10.10.40.0 | 255.255.255.224 | 10.10.0.10 | eth1 |
| R2 | 0.0.0.0 | 0.0.0.0 | 10.10.0.9 | eth0 |
| VPN-SRV | 0.0.0.0 | 0.0.0.0 | 10.10.50.1 | eth0 |
| WEB01 / WEB02 | 0.0.0.0 | 0.0.0.0 | 10.10.50.1 | eth0 |
| WEB01 / WEB02 | 10.200.10.0 | 255.255.255.0 | 10.10.50.2 | eth0 |
| WEB01 / WEB02 | 10.200.20.0 | 255.255.255.0 | 10.10.50.2 | eth0 |
| Hosts de VLAN | 0.0.0.0 | 0.0.0.0 | gateway de su VLAN (.1) | eth0 |

Notas:

- **Dos rutas por defecto en R-EDGE:** son la base del balanceo y el failover; las políticas por origen, puerto y protocolo van en tablas de ruteo aparte.
- **Rutas específicas en FW:** no usar un resumen /16 hacia PROXY, porque combinado con las rutas por defecto crearía bucles para direcciones `10.10.x.x` sin asignar.
- **Rutas a las redes VPN en WEB01 / WEB02:** VPN-SRV y los servidores web comparten segmento, así que un cliente VPN llega a ellos directamente y la respuesta debe volver por VPN-SRV. Por lo mismo, el tráfico VPN → DMZ no pasa por el firewall.
- **Sin NAT en VPN-SRV hacia la red interna:** el firewall debe ver los orígenes `10.200.x.x` para aplicar políticas distintas a VPN-ADMIN y VPN-USERS.

## Matriz de seguridad

Las reglas entre VLANs son ACL de R2 (estudiante 1); las demás son del firewall (estudiante 5), salvo la del portal, que se aplica en PROXY. En todos los casos se permite el tráfico de retorno de conexiones establecidas.

| Origen | Destino | Puerto/Servicio | Acción |
|---|---|---|---|
| VLAN USERS | VLAN ADMIN | Todos | Denegar |
| VLAN USERS | VLAN SERVERS | TCP 80, 443 | Permitir |
| VLAN USERS | VLAN SERVERS | Resto | Denegar |
| VLAN USERS | VLAN ZABBIX | Todos | Denegar |
| VLAN ADMIN | VLAN SERVERS | Todos | Permitir |
| VLAN ADMIN | VLAN USERS | Todos | Permitir |
| VLAN ADMIN | ZABBIX (10.10.30.2) | TCP 80, 443, 22 | Permitir |
| VLAN ADMIN | VLAN ZABBIX | ICMP (ping) | Permitir |
| VLAN SERVERS | VLAN ADMIN / USERS | Todos | Denegar |
| VLAN SERVERS | ZABBIX | TCP 10051 | Permitir |
| ZABBIX | VLAN SERVERS | TCP 10050, UDP 161, ICMP | Permitir |
| ZABBIX | R-EDGE | TCP 10050, ICMP | Permitir |
| R-EDGE | ZABBIX | TCP 10051 | Permitir |
| VLAN ADMIN | PROXY (portal) | TCP 8080 | Permitir |
| Cualquier otro | PROXY (portal) | TCP 8080 | Denegar |
| VLAN ADMIN / USERS | Internet | TCP 80, 443; UDP/TCP 53 | Permitir |
| VLAN SERVERS | Internet | TCP 80, 443; UDP/TCP 53 | Permitir |
| PROXY (10.10.0.6) | Internet | UDP/TCP 53 | Permitir |
| VLAN ADMIN | Internet | ICMP (ping) | Permitir |
| VLAN ADMIN, VPN-ADMIN | FW (el propio firewall) | TCP 22, ICMP | Permitir |
| VLAN ADMIN | DMZ | TCP 22, 80, 443; ICMP | Permitir |
| VLAN USERS | DMZ | TCP 80, 443 | Permitir |
| DMZ | VLANs internas | Todos | Denegar |
| WEB01 | Internet (ngrok) | TCP 443; UDP/TCP 53 | Permitir |
| Internet | VPN-SRV | UDP 51820 | Permitir |
| Internet | DMZ / VLANs | Todos | Denegar |
| VPN-ADMIN | VLAN ADMIN / SERVERS / USERS | Todos | Permitir |
| VPN-ADMIN | ZABBIX | TCP 80, 443 | Permitir |
| VPN-USERS | VLAN ADMIN | Todos | Denegar |
| VPN-USERS | VLAN SERVERS | TCP 80, 443 | Permitir |
| VPN-USERS | VLAN USERS | Todos | Permitir |
| VPN-USERS | ZABBIX | Todos | Denegar |
| VPN-ADMIN / VPN-USERS | Internet (full tunnel) | TCP 80, 443; UDP/TCP 53 | Permitir |
| Cualquiera | Cualquiera | Todos | Denegar y registrar |
