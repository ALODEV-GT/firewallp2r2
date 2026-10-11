# XelajuNetwork: bitácora de pruebas

Lista de todo lo que hay que probar, en el orden de montaje de `configuraciones.md` (sección 2.3). Cada fase depende de la anterior: no avances si una prueba de la fase actual falla.

## Cómo usarla

- **Estado:** marca cada prueba con `OK`, `FALLA` o `N/A`. Vacío significa pendiente.
- **Evidencia:** anota el nombre de la captura de pantalla o del archivo de salida. El enunciado exige demostrar con evidencias tanto lo permitido como lo bloqueado.
- **Fallas:** cada `FALLA` se registra también en la tabla de incidencias del final, con su causa y su corrección.
- **Responsable:** el prefijo del identificador indica quién ejecuta la prueba.

| Prefijo | Componente | Responsable |
|---|---|---|
| PRE | Datos previos | Todos |
| LAN, ACL, DHCP, ZBX | LAN, ACL, DHCP y Zabbix | Estudiante 1 |
| PRX | Proxy | Estudiante 2 |
| WAN | Multi-WAN | Estudiante 3 |
| VPN, DMZ | VPN y DMZ | Estudiante 4 |
| FW, IDS, CAP | Firewall, IDS y capturas | Estudiante 5 |
| ENL, INT | Enlaces e integración | Todos |

## Fase 0: datos previos

| ID | Dato a confirmar | Cómo | Valor esperado | Estado | Valor real y notas |
|---|---|---|---|---|---|
| PRE-01 | Red del teléfono 1 (ISP1) | `ip -4 addr show` e `ip route` en el anfitrión del estudiante 3 | Red, IP y gateway anotados | | |
| PRE-02 | Red del teléfono 2 (ISP2) | Igual, con el segundo teléfono | Red distinta de la del teléfono 1 | | |
| PRE-03 | Interfaces reales de FW | `ip link` en FW | Tres interfaces Ethernet identificadas (WAN, interna, DMZ) | OK | WAN `enp3s0`, interna `enx00e04c360188`, DMZ `enx00e04c3604ff` |
| PRE-04 | Interfaces reales de PROXY | `ip link` en PROXY | `enp0s31f6` hacia FW, `enx9c69d3101d16` hacia R2 | | |
| PRE-05 | Interfaz física de cada anfitrión | `ip link` en los anfitriones de los estudiantes 1, 3 y 4 | Una interfaz Ethernet libre para el cable | | |
| PRE-06 | Paquetes instalados | `dpkg -l` de los paquetes de la sección 2.1 en cada nodo | Todos instalados antes de cablear | | |
| PRE-07 | Hora y zona horaria | `timedatectl` en cada nodo | `America/Guatemala` y hora correcta | | |
| PRE-08 | Credenciales | Token de ngrok y contraseña de la base de Zabbix | Definidos, fuera de los documentos | | |

## Fase 1: LAN interna

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| LAN-01 | Puertos y VLAN de SW1 | Anfitrión de SW1: `ovs-vsctl show` | `tap-r2` con `trunks: [10, 20, 30, 40]`; cada puerto de acceso con su `tag` | | |
| LAN-02 | Subinterfaces de R2 | R2: `ip -br addr` | `eth1.10`, `eth1.20`, `eth1.30` y `eth1.40` con su gateway | | |
| LAN-03 | Gateway de la VLAN 10 | PC-ADMIN01: `ping -c 3 10.10.10.1` | Responde | | |
| LAN-04 | Gateway de la VLAN 30 | ZABBIX: `ping -c 3 10.10.30.1` | Responde | | |
| LAN-05 | Gateway de la VLAN 40 | SRV01: `ping -c 3 10.10.40.1` | Responde | | |
| LAN-06 | Inter-VLAN sin ACL | PC-ADMIN01: `ping -c 3 10.10.40.10` (antes de cargar las ACL) | Responde | | |
| LAN-07 | Etiquetas 802.1Q en la troncal | R2: `tcpdump -e -ni eth1 -c 10 vlan` durante un ping | Tramas con `vlan 10`, `vlan 40`, etc. | | |
| LAN-08 | Reenvío activo | R2: `sysctl net.ipv4.ip_forward` | `1` | | |

## Fase 2: enlaces entre equipos

Con FW en política abierta temporal, como indica la sección 2.3.

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| ENL-01 | R2 – PROXY | R2: `ping -c 3 10.10.0.9` | Responde | OK | 2026-10-11, desde FW a través del proxy: R2, las cuatro puertas de enlace y los cinco equipos de las VLAN responden (10 de 10). Falló el 2026-10-09; ver incidencia 1 |
| ENL-02 | PROXY – FW | PROXY: `ping -c 3 10.10.0.5` | Responde | OK | 2026-10-09, desde FW: PROXY 3/3 por sus dos direcciones; su DNS (`10.10.0.9`) responde |
| ENL-03 | FW – R-EDGE | FW: `ping -c 3 10.10.0.1` | Responde | OK | 2026-10-05: 3/3 desde FW; además Internet responde a través de R-EDGE (8.8.8.8 y 1.1.1.1, 3/3) |
| ENL-04 | FW – DMZ | FW: `ping -c 3 10.10.50.2` y `ping -c 3 10.10.50.10` | Responden | OK | 2026-10-05: VPN-SRV y WEB01 3/3; WEB01 y WEB02 responden HTTP 200 (misma MAC: es una sola máquina) |
| ENL-05 | Reenvío en cada router | R-EDGE, FW, PROXY y VPN-SRV: `sysctl net.ipv4.ip_forward` | `1` en todos | | |
| ENL-06 | Rutas de ida y vuelta | PC-ADMIN01: `ping -c 3 10.10.0.1` | Responde (atraviesa R2, PROXY y FW) | | |
| ENL-07 | Ruta hacia la DMZ | PC-ADMIN01: `ping -c 3 10.10.50.10` | Responde | | |

## Fase 3: Multi-WAN, balanceo y failover

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| WAN-01 | Salida por ISP1 | R-EDGE: `ping -c 3 -I eth0 -m 17 1.1.1.1` | Responde | | |
| WAN-02 | Salida por ISP2 | R-EDGE: `ping -c 3 -I eth1 -m 18 1.1.1.1` | Responde | | |
| WAN-03 | Servicio activo | R-EDGE: `systemctl status multiwan` y `journalctl -t multiwan -n 5` | Activo; última línea `ISP1=up ISP2=up` | | |
| WAN-04 | Tablas y reglas | R-EDGE: `ip rule`, `ip route show table 101`, `ip route show table 102` | Marcas 1 y 2 hacia 101 y 102; cada tabla con su ruta por defecto y la red de su enlace | | |
| WAN-05 | NAT de salida | PC-ADMIN01: `ping -c 3 8.8.8.8` | Responde | | |
| WAN-06 | Reglas generadas del archivo | R-EDGE: `nft list chain ip mwan politicas` | Una regla por línea de `politicas.conf` | | |
| WAN-07 | Política HTTPS por ISP1 | R-EDGE: `tcpdump -ni eth0 tcp port 443` mientras PC-USER01 abre un sitio HTTPS | El tráfico aparece en `eth0` y no en `eth1` | | |
| WAN-08 | Otro tráfico del mismo origen por ISP2 | R-EDGE: `tcpdump -ni eth1 tcp port 80` mientras PC-ADMIN01 ejecuta `curl http://neverssl.com` | El HTTP de PC-ADMIN01 sale por `eth1`; su HTTPS, por `eth0` | | |
| WAN-09 | DNS por ISP2 | R-EDGE: `tcpdump -ni eth1 udp port 53` mientras un cliente navega | Consultas con origen traducido saliendo por `eth1` | | |
| WAN-10 | Registro de política e ISP | R-EDGE: `journalctl -k \| grep MWAN \| tail` | Líneas `MWAN-POL` y `MWAN-OUT` con IP de origen e ISP | | |
| WAN-11 | Balanceo sin política | PC-ADMIN01: ping a 8 destinos distintos; R-EDGE: `journalctl -k \| grep -c "MWAN-OUT ISP1"` y lo mismo con `ISP2` | Conexiones repartidas entre los dos ISP | | |
| WAN-12 | Origen conservado tras el proxy | R-EDGE: `tcpdump -ni eth2 tcp port 80` mientras PC-USER01 navega por HTTP | El origen es `10.10.20.10`, no `10.10.0.6` | | |
| WAN-13 | Failover de ISP1 | Anfitrión: `ip link set br-isp1 down`; R-EDGE: `journalctl -t multiwan -f` | En unos 10 s, `ISP1=down ISP2=up`; la navegación continúa | | |
| WAN-14 | Recuperación de ISP1 | Anfitrión: `ip link set br-isp1 up` | `ISP1=up ISP2=up` y vuelve la política normal | | |
| WAN-15 | Failover de ISP2 | Repetir WAN-13 y WAN-14 con `br-isp2` | El tráfico de ISP2 pasa a ISP1 y luego regresa | | |
| WAN-16 | Cambio de política sin tocar el script | Editar una línea de `politicas.conf`, ejecutar `mwan-apply.sh` y repetir WAN-07 | El tráfico cambia de ISP | | |

## Fase 4: ACL y DHCP restringido

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| ACL-01 | USERS a ADMIN, denegado | PC-USER01: `ping -c 3 10.10.10.10` | Sin respuesta | | |
| ACL-02 | USERS a SERVERS, servicio permitido | PC-USER01: `curl -I http://10.10.40.10` | Responde | | |
| ACL-03 | USERS a SERVERS, servicio denegado | PC-USER01: `ssh 10.10.40.10` | Sin conexión | | |
| ACL-04 | USERS a gestión, denegado | PC-USER01: `ping -c 3 10.10.30.2` | Sin respuesta | | |
| ACL-05 | ADMIN a SERVERS, permitido | PC-ADMIN01: `ping -c 3 10.10.40.10` y `ssh 10.10.40.10` | Responde y conecta | | |
| ACL-06 | SERVERS a ADMIN, denegado | SRV01: `ping -c 3 10.10.10.10` | Sin respuesta | | |
| ACL-07 | Registro de bloqueos | R2: `journalctl -k \| grep ACL-DENY \| tail` | Una línea por cada intento denegado | | |
| DHCP-01 | Escucha solo en la VLAN 20 | R2: `journalctl -u isc-dhcp-server \| grep -i listening` | Solo `eth1.20` | | |
| DHCP-02 | Equipo registrado | PC-USER01: `dhclient -v eth0` | Recibe `10.10.20.10`, gateway `10.10.20.1` | | |
| DHCP-03 | IP fija | PC-USER01: liberar y pedir de nuevo (`dhclient -r eth0; dhclient -v eth0`) | Recibe otra vez `10.10.20.10` | | |
| DHCP-04 | DNS entregado | PC-USER01: `cat /etc/resolv.conf` | `nameserver 10.10.0.9` | | |
| DHCP-05 | Equipo no registrado | Quitar a PC-USER02 de `usuarios.csv`, ejecutar `dhcp-reservas.sh` y pedir IP en PC-USER02 | No recibe IP; en el log de R2 hay DISCOVER sin OFFER | | |
| DHCP-06 | Registro de un equipo | Volver a añadir a PC-USER02 al CSV, ejecutar el script y pedir IP | Recibe `10.10.20.11` | | |

## Fase 5: proxy Squid

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| PRX-01 | Servicios activos | PROXY: `systemctl is-active squid dnsmasq portal-squid` | `active` en los tres | | |
| PRX-02 | Puertos de Squid | PROXY: `ss -ltn \| grep -E '3128\|3129\|3130'` | Los tres en escucha | | |
| PRX-03 | Caché DNS | PC-USER01: `getent hosts www.debian.org` | Resuelve usando `10.10.0.9` | | |
| PRX-04 | Proxy transparente | Navegador de PC-USER01: revisar la configuración de red | Sin proxy configurado y navega | | |
| PRX-05 | HTTP permitido | PC-USER01: `curl -I http://neverssl.com` | `200`; línea `TCP_MISS/200` en el log | | |
| PRX-06 | HTTP bloqueado | PC-USER01: `curl -I http://www.youtube.com` | `403`; línea `TCP_DENIED/403` | | |
| PRX-07 | HTTPS permitido | PC-USER01: `curl -I https://www.debian.org` | `200`; línea `TCP_TUNNEL/200` con `splice` | | |
| PRX-08 | HTTPS bloqueado | PC-USER01: abrir `https://www.youtube.com` | Falla; línea con `terminate` | | |
| PRX-09 | Lista diferenciada | PC-ADMIN01: abrir `https://www.youtube.com` | Carga (no está en `admins_blacklist`) | | |
| PRX-10 | Bloqueo para ADMIN | PC-ADMIN01: abrir `https://www.ilovepdf.com` | Falla | | |
| PRX-11 | Cambio en caliente | Añadir un dominio a `users_blacklist`, ejecutar `squid -k reconfigure` y probarlo desde PC-USER01 | Se bloquea sin reiniciar ni editar `squid.conf` | | |
| PRX-12 | Campos del registro | PROXY: `tail /var/log/squid/access.log` | Fecha y hora, IP de origen, resultado, método y dominio | | |
| PRX-13 | Sin errores de resolución | PROXY: `grep -c '/409' /var/log/squid/access.log` tras navegar | `0` | | |
| PRX-14 | Portal desde ADMIN | PC-ADMIN01: abrir `http://10.10.0.9:8080` | Muestra solicitudes, dominios, IP de origen, permitido o bloqueado y estadísticas | | |
| PRX-15 | Filtros del portal | En el portal, filtrar por la IP `10.10.20.10` y por un dominio | Solo aparecen las solicitudes que coinciden | | |
| PRX-16 | Portal denegado a USERS | PC-USER01: `curl -m 5 http://10.10.0.9:8080` | Sin acceso; `PORTAL-DENY` en `journalctl -k` de PROXY | | |
| PRX-17 | Tráfico no web sin proxy | PC-ADMIN01: `ping -c 3 8.8.8.8` | Responde; no aparece en el log de Squid | | |

## Fase 6: VPN y DMZ

El cliente es PC-REMOTO, en `br-isp1` del anfitrión del estudiante 3, con perfiles entregados por el estudiante 4.

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| DMZ-01 | Servidor web local | WEB01: `curl -I http://localhost` | `200` | | |
| DMZ-02 | Direccionamiento estático | WEB01: `ip -4 addr` | Solo `10.10.50.10/28`, sin IP pública | | |
| DMZ-03 | Acceso desde ADMIN | PC-ADMIN01: `curl -I http://10.10.50.10` | `200` | | |
| DMZ-04 | Acceso desde USERS | PC-USER01: `curl -I http://10.10.50.10` | `200` | | |
| DMZ-05 | Túnel de ngrok | WEB01: `ngrok http 80` | Estado `online` y una URL pública | | |
| DMZ-06 | Acceso externo | Un equipo ajeno al proyecto, con sus propios datos, abre la URL de ngrok | Página de WEB01 | | |
| VPN-01 | Servidor activo | VPN-SRV: `wg show` | `wg0` en el puerto 51820 con sus peers | | |
| VPN-02 | Handshake | PC-REMOTO: `wg-quick up remote-admin1`; VPN-SRV: `wg show` | `latest handshake` reciente y contadores de tráfico | | |
| VPN-03 | IP según el tipo de usuario | PC-REMOTO: `ip -4 addr show remote-admin1` | Dirección de `10.200.10.0/28` | | |
| VPN-04 | VPN-ADMIN a VLAN ADMIN | Peer remote-admin1: `ping -c 3 10.10.10.10` | Responde | | |
| VPN-05 | VPN-ADMIN a VLAN SERVERS | Peer remote-admin1: `curl -I http://10.10.40.10` | `200` | | |
| VPN-06 | VPN-ADMIN a VLAN USERS | Peer remote-admin1: `ping -c 3 10.10.20.10` | Responde | | |
| VPN-07 | VPN-USERS a VLAN ADMIN, bloqueado | Peer remote-user1: `ping -c 3 10.10.10.10` | Sin respuesta; `FW-DENY` en FW | | |
| VPN-08 | VPN-USERS a SERVERS, servicio autorizado | Peer remote-user1: `curl -I http://10.10.40.10` | `200` | | |
| VPN-09 | VPN-USERS a SERVERS, servicio no autorizado | Peer remote-user1: `ssh 10.10.40.10` | Sin conexión; `FW-DENY` en FW | | |
| VPN-10 | VPN-USERS a VLAN USERS | Peer remote-user1: `ping -c 3 10.10.20.10` | Responde | | |
| VPN-11 | Full Tunnel | Peer con `AllowedIPs = 0.0.0.0/0`: `curl ifconfig.me` | Muestra la IP pública de un ISP del proyecto | | |
| VPN-12 | Registro de peers | VPN-SRV: tabla de peers o `peers.csv` | Nombre, tipo, IP y clave pública de cada peer | | |

## Fase 7: firewall, IDS y capturas

Con las reglas definitivas de FW cargadas.

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| FW-01 | Denegación por defecto | FW: `nft list ruleset` | `policy drop` en `input` y `forward` | OK | Comprobado en FW el 2026-10-04; además, 41 de 41 flujos correctos con `firewall_config/pruebas/prueba-reglas.sh` (vecinos simulados) |
| FW-02 | Acceso permitido y registrado | PC-ADMIN01: `curl -I http://10.10.50.10`; FW: `tail /var/log/firewall/fw.log` | `200` y línea `FW-ALLOW` | | |
| FW-03 | Acceso denegado y registrado | PC-USER01: `ssh 10.10.50.10` | Sin conexión y línea `FW-DENY` | | |
| FW-04 | DMZ aislada de la red interna | WEB01: `ping -c 3 10.10.10.10` | Sin respuesta; `FW-DENY` | | |
| FW-05 | Internet sin acceso directo a la DMZ | PC-REMOTO, sin VPN: `curl -m 5 http://<IP WAN de R-EDGE>` | Conexión rechazada o sin respuesta; nunca la página de WEB01 | | |
| FW-06 | Seguimiento de conexiones | Repetir FW-02 y contar líneas nuevas en `fw.log` | Una sola línea por conexión | | |
| FW-07 | Salida de ngrok | FW: `grep 10.10.50.10 /var/log/firewall/fw.log` con el túnel activo | `FW-ALLOW` hacia el puerto 443 | | |
| FW-08 | Campos del registro | FW: `tail /var/log/firewall/fw.log` | Fecha y hora, `SRC`, `DST`, `PROTO`, `DPT` y acción | | |
| FW-09 | Registros protegidos | FW, con un usuario común: `cat /var/log/firewall/fw.log` | Permiso denegado | OK | Usuario `firewall`: "Permission denied" |
| FW-10 | Permisos tras escribir | FW: `ls -l /var/log/firewall` | `root:adm` con `640` | OK | `-rw-r----- root adm fw.log` tras escribir rsyslog |
| IDS-01 | Suricata activo | FW: `systemctl is-active suricata` | `active` | OK | Activo con las tres interfaces y 3 reglas cargadas; alertas aún sin probar |
| IDS-02 | Escaneo de puertos | PC-ADMIN01: `nmap -sS 10.10.50.10`; FW: `tail /var/log/suricata/fast.log` | Alerta con sid `1000001` | | |
| IDS-03 | Múltiples intentos de conexión | PC-ADMIN01: `for i in $(seq 8); do nc -z -w 1 10.10.50.10 22; done` | Alerta con sid `1000002` | | |
| IDS-04 | Firma definida | PC-ADMIN01: `curl http://10.10.50.10/prueba-ids` | Alerta con sid `1000003` | | |
| CAP-01 | Captura en el firewall | FW: `tcpdump -ni <interfaz DMZ> -w /tmp/dmz.pcap` durante DMZ-03; abrir en Wireshark | Solicitud HTTP completa analizada | | |
| CAP-02 | Captura por SPAN | Anfitrión de SW1: Wireshark en `span0` durante un ping entre VLANs | Tramas con etiqueta 802.1Q de otros equipos | | |

## Fase 8: monitoreo con Zabbix

| ID | Prueba | Desde y comando | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| ZBX-01 | Frontend desde ADMIN | PC-ADMIN01: abrir `http://10.10.30.2/zabbix` | Página de inicio de sesión | | |
| ZBX-02 | Frontend denegado a USERS | PC-USER01: `curl -m 5 http://10.10.30.2/zabbix` | Sin acceso | | |
| ZBX-03 | Agente de R-EDGE disponible | Zabbix, lista de hosts | R-EDGE con el indicador del agente en verde | | |
| ZBX-04 | Métricas de ISP1 | Dashboard: gráfica de `eth0` de R-EDGE | Tráfico de entrada y de salida | | |
| ZBX-05 | Métricas de ISP2 | Dashboard: gráfica de `eth1` de R-EDGE | Tráfico de entrada y de salida | | |
| ZBX-06 | Failover visible | Dashboard durante WAN-13 | El tráfico de ISP1 cae y el de ISP2 sube | | |

## Fase 9: integración de los flujos

| ID | Flujo | Prueba | Resultado esperado | Estado | Evidencia y notas |
|---|---|---|---|---|---|
| INT-01 | A: navegación | PC-USER01 abre un sitio permitido y uno bloqueado | El permitido carga; el bloqueado falla. Queda rastro en Squid, FW y R-EDGE | | |
| INT-02 | A con failover | Repetir INT-01 con `br-isp1` abajo | La navegación continúa por ISP2 | | |
| INT-03 | B: VPN | Desde PC-REMOTO, un peer ADMIN y un peer USER acceden a las VLAN | Cada uno llega solo a lo autorizado | | |
| INT-04 | C: ngrok | Un usuario externo abre la URL pública | Página de WEB01, sin IP pública en el servidor | | |
| INT-05 | Monitoreo | Dashboard de Zabbix durante INT-01 a INT-04 | Tráfico visible en ambos ISP | | |
| INT-06 | Reinicio | Reiniciar todos los nodos y repetir INT-01 e INT-03 | Todo vuelve a funcionar sin intervención manual | | |

## Incidencias

| N.º | Fecha | Prueba | Qué falló | Causa | Corrección | Responsable |
|---|---|---|---|---|---|---|
| 1 | 2026-10-09 | ENL-01, ENL-06 | Desde FW no responden R2 ni ningún equipo de las VLAN | No se determinó con certeza: el 2026-10-11, al revisar el proxy, el reenvío ya estaba activo (`ip_forward` y reglas en `DOCKER-USER`) y R2 respondía | Resuelto el 2026-10-11 | Estudiantes 1 y 2 |
| 2 | 2026-10-09 | IDS-01 | Suricata quedó en estado fallido tras reiniciar FW | Arrancó antes de que existieran los adaptadores USB-Ethernet | Archivo de systemd que espera a las interfaces y reintenta (`firewall_config`, sección 7.3); confirmado con el reinicio del 2026-10-11 | Estudiante 5 |
| 3 | 2026-10-11 | PRX-04, INT-01 | El HTTP de PC-USER01 no llegaba a Squid ni a Internet | En el proxy: el tráfico de las VLAN salía por el Wi-Fi del equipo y lo descartaba la cadena `FORWARD` de Docker; faltaba la regla `socket transparent`; y Tailscale deja `src_valid_mark=1`, con lo que el kernel descartaba los paquetes marcados para TPROXY | Reglas `from 10.10.0.0/16` hacia la tabla 101, regla `socket transparent`, `accept_local=1` en las dos interfaces del proyecto, todo en `xelajunetwork-tproxy-on`. Comprobado: `curl -I http://neverssl.com` desde PC-USER01 da 200, Squid registra `10.10.20.10 TCP_MISS/200` y el firewall `FW-ALLOW` con origen `10.10.20.10` | Estudiantes 2 y 5 |
