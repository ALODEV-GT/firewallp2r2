# Prompt: diagrama de topología de XelajuNetwork en Figma

Usa las herramientas de Figma para crear un diagrama de topología de red en un archivo nuevo llamado "XelajuNetwork – Topología". Es para la documentación de un proyecto universitario de redes, así que lo leerá un catedrático que necesita ver de un vistazo qué equipo se conecta con cuál, por qué interfaz y con qué IP. La prioridad es que cada enlace y cada dirección se lean sin ambigüedad; la estética es secundaria.

El archivo `direccionamiento.md`, en esta misma carpeta, es la fuente de verdad de todas las direcciones. Léelo antes de dibujar y, si algo de este prompt lo contradice, gana ese archivo. No inventes equipos, enlaces ni direcciones que no aparezcan allí.

## Qué representa la red

Es una red empresarial con una cadena principal en serie y una rama lateral:

- Cadena principal, de arriba hacia abajo: ISP1 e ISP2 → R-EDGE → FW → PROXY → R2 → SW1 → cuatro VLANs.
- Rama lateral: del firewall sale una tercera interfaz hacia la DMZ, donde están VPN-SRV, WEB01 y WEB02.

Dibuja la cadena principal en vertical, con Internet arriba y las VLANs abajo, y la DMZ a la derecha del firewall. Ese orden coincide con el diagrama del enunciado del proyecto.

## Equipos y zonas

Agrupa los equipos en zonas con un contorno punteado y un título, porque cada zona corresponde a un integrante del equipo:

| Zona | Equipos | Responsable |
|---|---|---|
| WAN / Multi-WAN | Nubes ISP1 e ISP2, R-EDGE | Estudiante 3 |
| Seguridad perimetral | FW (firewall nftables + IDS) | Estudiante 5 |
| Proxy | PROXY (Squid transparente) | Estudiante 2 |
| DMZ y VPN | VPN-SRV (WireGuard), WEB01, WEB02 (opcional) | Estudiante 4 |
| LAN interna | R2, SW1, las cuatro VLANs y sus equipos | Estudiante 1 |

Usa una forma distinta por tipo de equipo (nube, router, firewall, proxy, switch, servidor, PC) y mantén la misma forma para todos los equipos del mismo tipo.

## Enlaces y direcciones

Rotula cada extremo de cada enlace con el nombre de la interfaz y su IP, y el centro del enlace con la red. Estos son los enlaces:

| Enlace | Red | Extremo A | Extremo B |
|---|---|---|---|
| ISP1 – R-EDGE | 192.168.41.0/24 (marcador) | gateway 192.168.41.1 | R-EDGE eth0: 192.168.41.2 |
| ISP2 – R-EDGE | 192.168.42.0/24 (marcador) | gateway 192.168.42.1 | R-EDGE eth1: 192.168.42.2 |
| R-EDGE – FW | 10.10.0.0/30 | R-EDGE eth2: 10.10.0.1 | FW eth0: 10.10.0.2 |
| FW – PROXY | 10.10.0.4/30 | FW eth1: 10.10.0.5 | PROXY eth0: 10.10.0.6 |
| PROXY – R2 | 10.10.0.8/30 | PROXY eth1: 10.10.0.9 | R2 eth0: 10.10.0.10 |
| FW – DMZ | 10.10.50.0/28 | FW eth2: 10.10.50.1 | VPN-SRV .2, WEB01 .10, WEB02 .11 |
| R2 – SW1 | Troncal 802.1Q | R2 eth1 (subinterfaces .10, .20, .30, .40) | SW1 puerto troncal |

Cada ISP es un teléfono celular conectado por USB; rotula las nubes "ISP1 (teléfono 1)" e "ISP2 (teléfono 2)". Sus direcciones son marcadores que cambiarán según la red de cada teléfono; márcalas con un asterisco y una nota al pie que lo diga.

El enlace R2 – SW1 es una troncal: dibújalo con un trazo más grueso o de otro color que los demás y rotúlalo "Troncal 802.1Q". SW1 es de capa 2 y no lleva IP. Rotúlalo "SW1 (Open vSwitch)" y rotula sus puertos: `tap-r2` es la troncal, los puertos de acceso están indicados en la tabla de VLANs y `span0` es un puerto espejo (SPAN) para captura con Wireshark.

## VLANs

Debajo de SW1 dibuja cuatro contenedores, uno por VLAN, cada uno con su número, nombre, red y gateway (la subinterfaz de R2):

| VLAN | Nombre | Red | Gateway | Equipos dentro |
|---|---|---|---|---|
| 10 | Administración | 10.10.10.0/27 | 10.10.10.1 | PC-ADMIN01: 10.10.10.10 (puerto tap-admin01 de SW1) |
| 20 | Usuarios | 10.10.20.0/25 | 10.10.20.1 | PC-USER01: 10.10.20.10 (tap-user01); PC-USER02: 10.10.20.11 (tap-user02) |
| 30 | Zabbix | 10.10.30.0/28 | 10.10.30.1 | ZABBIX: 10.10.30.2 (tap-zabbix) |
| 40 | Servidores | 10.10.40.0/27 | 10.10.40.1 | SRV01: 10.10.40.10 (tap-srv01) |

Dale a cada VLAN un color propio y úsalo solo para esa VLAN. En la VLAN 20 añade la etiqueta "DHCP restringido por MAC (servicio en R2, eth1.20)", porque es la única red con DHCP; todas las demás usan direccionamiento estático. El servidor DHCP no es un equipo aparte: corre en R2, así que no lo dibujes como nodo.

## VPN y ngrok

Estos dos elementos son túneles lógicos y no cables, así que dibújalos con línea discontinua para distinguirlos de los enlaces físicos:

- **WireGuard:** una línea discontinua desde un grupo "Usuarios remotos", colocado junto a las nubes de Internet, hasta VPN-SRV. Rotúlala "WireGuard UDP 51820". Dentro del grupo de usuarios remotos muestra los dos rangos: VPN-ADMIN 10.200.10.0/28 (peers .2 a .8) y VPN-USERS 10.200.20.0/27 (peers .2 a .10). En VPN-SRV indica la interfaz `wg0` con 10.200.10.1 y 10.200.20.1.
- **ngrok:** una línea discontinua desde WEB01 hasta una nube "ngrok (URL pública)" junto a Internet, con una flecha que salga de WEB01, porque el túnel se inicia desde dentro. Rotúlala "Túnel ngrok TCP 443 (saliente)".

## Leyenda

Incluye una leyenda en una esquina que explique: enlace físico, troncal 802.1Q, túnel lógico, el color de cada VLAN y el significado del asterisco de las direcciones WAN.

## Criterios de terminado

- Aparecen todos los equipos de la tabla de direccionamiento de `direccionamiento.md` y ninguno más.
- Cada interfaz con IP en esa tabla está rotulada en el diagrama con su nombre y su dirección.
- Ningún rótulo se superpone con otro ni con una línea, y los enlaces no se cruzan salvo que sea inevitable.
- El texto se lee al exportar el frame a PNG en tamaño carta horizontal.

Cuando termines, toma una captura del resultado, revísala contra estos criterios y corrige lo que falle antes de darlo por terminado. Al final, dime el enlace del archivo y cualquier dato que hayas tenido que suponer.
