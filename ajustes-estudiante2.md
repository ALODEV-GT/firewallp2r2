# Ajustes para PROXY (Estudiante 2)

Esta guía está escrita para el agente que asiste al estudiante 2 en el equipo del proxy. Parte de lo que el propio estudiante documentó en `Estudiante2.md` (rama `estudiante2`) y de lo que el firewall del grupo ha observado en la red. Explica una decisión de diseño que ya se tomó y qué hay que cambiar en el proxy para cumplirla.

El equipo del proxy es una máquina personal con Docker y Tailscale. Todo lo que se propone aquí respeta lo que el estudiante ya decidió: configuración temporal, reversible, y sin tocar `/etc/nftables.conf` ni las reglas de Docker y Tailscale. Antes de cambiar nada, inspecciona el estado real y compáralo con cada punto.

## 1. La decisión: Squid debe conservar la IP del cliente

Hoy Squid está en modo `intercept`: recibe el HTTP de los clientes y sale hacia Internet con la IP del proxy, `10.10.0.6`. El apartado 9 de `Estudiante2.md` lo reconoce y lo deja "a considerar por el Multi-WAN del grupo".

El grupo decidió que Squid trabaje en modo **TPROXY**, que sale conservando la IP del cliente. Motivos:

- **Lo exige el enunciado al estudiante 3.** Sus políticas de salida son por IP de origen, puerto y protocolo, y deben poder aplicarse "aun cuando el tráfico haya sido procesado por el proxy". Si toda la web llega a R-EDGE como `10.10.0.6`, esas políticas dejan de distinguir equipos.
- **El firewall aplica denegación por defecto.** Solo permite salir por los puertos 80 y 443 a las redes de las VLAN. A `10.10.0.6` solo le permite DNS. Con el modo actual, **toda la navegación interceptada queda bloqueada en el firewall**.

Esto no cambia nada de lo que el enunciado pide al proxy: sigue siendo transparente, sigue interceptando HTTP y las listas siguen aplicándose por red de origen.

## 2. Lo que se ve hoy desde el firewall

| Observación | Significado |
|---|---|
| `10.10.0.6` y `10.10.0.9` responden al ping | Los dos enlaces del proxy están bien |
| `10.10.0.9` responde consultas DNS | Hay un servicio DNS escuchando; ver sección 3.5 |
| El portal en el puerto 8080 responde 403 al firewall | Correcto: el firewall no es de la VLAN de Administración |
| En la traza hacia las VLAN, el proxy aparece como primer salto y después no hay nada | El proxy enruta, pero los paquetes no llegan a R2 o no vuelven; ver sección 3.1 |
| Nunca ha llegado al firewall un paquete con origen en las VLAN | Lo mismo, en el otro sentido |
| Cientos de conexiones de `10.10.0.6` a Internet (TCP 443 y 80, UDP 3478) bloqueadas | Es el tráfico propio del equipo (navegador, Tailscale, Docker); ver sección 3.6 |

## 3. Qué hay que cambiar

### 3.1 Primero: que el tráfico reenviado atraviese el proxy

Es lo que hoy impide cualquier prueba con las VLAN, y es independiente de Squid.

`Estudiante2.md` dice que la cadena de reenvío del proyecto tiene `policy accept` con prioridad `-50`, para que se evalúe antes que la cadena `FORWARD` de Docker, que tiene `policy drop`. Eso no basta: en nftables, que una cadena acepte un paquete no impide que otra cadena del mismo punto lo descarte después. El paquete pasa por todas, y un descarte en cualquiera es definitivo. **Causa probable, sin confirmar:** la cadena `FORWARD` de Docker está descartando el tráfico entre R2 y el firewall.

Cómo comprobarlo, mientras un equipo de una VLAN hace ping a `8.8.8.8`:

```bash
sudo iptables -L FORWARD -v -n | head -5        # ¿sube el contador de la política DROP?
sudo tcpdump -ni enp0s31f6 icmp                 # ¿sale el paquete hacia el firewall?
```

Si el paquete entra por la interfaz de R2 y no sale por la del firewall, la corrección es aceptar ese tráfico en la cadena que Docker reserva para reglas del usuario, que se evalúa antes que las suyas y que Docker no borra:

```bash
sudo iptables -I DOCKER-USER -i enx9c69d3101d16 -o enp0s31f6 -j ACCEPT
sudo iptables -I DOCKER-USER -i enp0s31f6 -o enx9c69d3101d16 -j ACCEPT
```

Para revertirlo, las mismas dos líneas con `-D` en lugar de `-I`. No modifica ninguna regla de Docker ni de Tailscale.

Comprobación: desde el proxy, `ping 10.10.0.10` (R2); desde un equipo de la VLAN 10, `ping 10.10.0.5` (firewall).

### 3.2 Squid: de `intercept` a `tproxy`

En `/etc/squid/squid.conf`, cambia solo el modo del puerto interceptado:

```
http_port 3128
http_port 3129 tproxy
```

El puerto 3128 debe seguir existiendo: Squid exige al menos un puerto normal. Las ACL, las listas y las reglas `http_access` no cambian.

Squid necesita poder abrir conexiones con una dirección de origen ajena; al arrancar como servicio de systemd ya tiene ese permiso. Valida con `sudo squid -k parse` y comprueba que la compilación soporta TPROXY: en `squid -v` debe aparecer `--enable-linux-netfilter`.

### 3.3 nftables: de `redirect` a `tproxy`

En la tabla `xelajunetwork_proxy`, la cadena que hoy redirige el puerto 80 se sustituye por esta. La cadena de reenvío del proyecto puede quedarse como está.

```
table ip xelajunetwork_proxy {
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;

    # Paquetes de conexiones que Squid ya atiende (incluidas las respuestas
    # de Internet, que llegan dirigidas a la IP del cliente).
    meta l4proto tcp socket transparent 1 meta mark set 1 accept

    # HTTP de Administración y Usuarios hacia Internet: se entrega a Squid.
    iifname "enx9c69d3101d16" ip saddr { 10.10.10.0/27, 10.10.20.0/25 } ip daddr != { 10.10.0.0/16, 10.200.0.0/16 } tcp dport 80 tproxy to :3129 meta mark set 1 accept
  }
}
```

Diferencias con la regla actual:

- **`tproxy` en lugar de `redirect`:** no cambia la dirección de destino del paquete; lo entrega a Squid tal cual.
- **Cadena de tipo `filter` con prioridad `mangle`:** `tproxy` no funciona en una cadena de tipo `nat`.
- **La primera regla es imprescindible:** sin ella, las respuestas de Internet (dirigidas a la IP del cliente) se reenviarían a R2 en lugar de entregarse a Squid.
- **Exclusión de `10.200.0.0/16`:** añade las redes VPN a la exclusión de destinos internos que ya existe.

### 3.4 Enrutamiento de los paquetes marcados y filtro de ruta inversa

Los paquetes marcados con `1` deben entregarse al propio equipo aunque su dirección de destino sea de Internet:

```bash
sudo ip rule add priority 100 fwmark 1 lookup 100
sudo ip route add local 0.0.0.0/0 dev lo table 100
```

La prioridad `100` coloca la regla antes que las de Tailscale. La marca `1` no coincide con las que usa Tailscale.

El filtro de ruta inversa debe desactivarse en las dos interfaces, porque las respuestas de Internet llegan por la del firewall con un destino que el equipo alcanzaría por la de R2:

```bash
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.enp0s31f6.rp_filter=0
sudo sysctl -w net.ipv4.conf.enx9c69d3101d16.rp_filter=0
```

Anota los valores anteriores (`sysctl net.ipv4.conf.all.rp_filter`, etc.) para poder restaurarlos.

### 3.5 DNS para los clientes

Los equipos de las VLAN 10 y 20 ya usan `10.10.0.9` como servidor DNS (lo entrega el DHCP de R2), y esa dirección ya responde. Hay que confirmar **qué servicio** contesta y que seguirá activo en la demostración: `sudo ss -lunp | grep ':53 '`.

Si se añade el filtrado de HTTPS de la sección 4, ese servicio debe ser una caché usada también por Squid (`dns_nameservers 127.0.0.1` en `squid.conf`). El motivo está explicado en esa sección.

### 3.6 Tráfico propio del equipo

Con el perfil `squid-firewall` activo, la ruta por defecto del equipo pasa por el firewall, y este bloquea todo lo que el propio equipo intenta hacer en Internet (salvo DNS). No es un fallo: el firewall no debe dar Internet al proxy. Pero llena de líneas el registro de auditoría del firewall.

Durante las pruebas y la demostración conviene cerrar el navegador y detener Tailscale (`sudo systemctl stop tailscaled`) y los contenedores que busquen Internet. Si el equipo necesita Internet propia para instalar paquetes, hazlo antes de activar `squid-firewall`.

### 3.7 Arranque y parada en un solo paso

La configuración actual vive en memoria y en `/tmp`, y se pierde al reiniciar. Para la demostración conviene reunirla en dos scripts, uno que la aplique y otro que la revierta, guardados fuera de `/tmp`. Mantiene la reversibilidad que el estudiante quiere y evita depender de recordar los comandos.

El de arranque debe hacer, en este orden:

1. Activar los perfiles `squid-firewall` y `squid-r2`.
2. Activar `ip_forward` y desactivar `rp_filter` (3.4).
3. Añadir la regla y la ruta de la tabla 100 (3.4).
4. Añadir las dos reglas de `DOCKER-USER` (3.1), si resultan necesarias.
5. Cargar la tabla `xelajunetwork_proxy` (3.3).
6. Arrancar el servicio DNS, Squid y el portal.

El de parada deshace lo mismo en orden inverso y restaura los valores anotados.

El enunciado pide entregar los scripts usados y documentarlos, así que estos dos deben ir al repositorio.

## 4. Opcional: filtrar también HTTPS

El enunciado solo exige interceptar HTTP, y eso queda cumplido con la sección 3. Pero casi todos los dominios de las listas (`facebook.com`, `youtube.com`, `ilovepdf.com`, …) solo funcionan por HTTPS. Sin este paso, **esos sitios no se bloquearán ni aparecerán en el registro**: su tráfico se enruta sin pasar por Squid. Para la demostración haría falta entonces tener en las listas algún dominio que funcione por HTTP.

Si se quiere bloquearlos, Squid puede leer el nombre del sitio en el saludo TLS (SNI) sin descifrar nada:

- **Paquete:** hace falta la compilación con OpenSSL (`squid-openssl`); en `squid -v` debe aparecer `--with-openssl`.
- **Puerto y reglas en `squid.conf`:**

  ```
  https_port 3130 tproxy ssl-bump tls-cert=/etc/squid/ssl/squid.pem generate-host-certificates=off

  acl admins_blocked_sni ssl::server_name "/etc/squid/admins_blacklist"
  acl users_blocked_sni  ssl::server_name "/etc/squid/users_blacklist"

  acl step1 at_step SslBump1
  ssl_bump peek step1
  ssl_bump terminate admins admins_blocked_sni
  ssl_bump terminate users users_blocked_sni
  ssl_bump splice all
  ```

  El certificado solo lo exige Squid para abrir el puerto; no se usa para descifrar. Se genera con `openssl req -new -newkey rsa:2048 -days 365 -nodes -x509`.
- **Regla de nftables:** una línea igual a la del puerto 80, con `tcp dport 443 tproxy to :3130`.
- **Caché DNS compartida:** antes de dejar pasar una conexión, Squid comprueba que la IP de destino corresponda al nombre del sitio. Si el cliente y Squid consultan servidores DNS distintos, parte de las conexiones permitidas falla con error 409. La solución es que ambos usen la misma caché en el proxy.
- **Registro:** añade `%ssl::>sni` y `%ssl::bump_mode` al `logformat` para que el portal pueda mostrar el dominio y si se bloqueó.

Esta configuración se validó de extremo a extremo con Squid 6.13 en Debian 13 (sección 4 de `configuraciones.md`, en `main`). **No se ha probado con Squid 7.7**, que es la versión de este equipo; valida con `squid -k parse` y con una prueba real antes de darla por buena.

## 5. Cómo comprobarlo

| Comprobación | Dónde y comando | Resultado esperado |
|---|---|---|
| El proxy reenvía | PC-ADMIN01: `ping 10.10.0.5` y `ping 8.8.8.8` | Responden |
| HTTP permitido | PC-USER01: `curl -I http://neverssl.com` | `200`; línea en `access.log` con origen `10.10.20.10` |
| HTTP bloqueado | PC-USER01: `curl -I http://<dominio de users_blacklist que funcione por HTTP>` | `403` y `TCP_DENIED` |
| **Origen conservado** | Proxy: `sudo tcpdump -ni enp0s31f6 tcp port 80` durante la prueba anterior | El origen es `10.10.20.10`, **no** `10.10.0.6` |
| Lista diferenciada | Repetir desde PC-ADMIN01 con un dominio que solo esté en `users_blacklist` | Carga |
| Tráfico no web | PC-ADMIN01: `ping 8.8.8.8` | Responde y no aparece en `access.log` |
| Portal | PC-ADMIN01: abrir `http://10.10.0.9:8080` | Muestra los registros |
| Portal denegado | PC-USER01: misma dirección | Sin acceso |

La cuarta comprobación es la que confirma el cambio. Si el origen sigue siendo `10.10.0.6`, Squid no está en modo TPROXY o falta la regla de la tabla 100, y el firewall bloqueará la conexión.

## 6. Qué no hay que hacer

- **No añadir NAT en el proxy.** Ya no lo hay y debe seguir así.
- **No pedir que el firewall deje salir a `10.10.0.6` por los puertos 80 o 443.** Con TPROXY no hace falta.
- **No redirigir desde R2.** Ya está corregido en `Estudiante2.md`; R2 solo enruta.
- **No modificar `/etc/nftables.conf` ni las cadenas de Docker y Tailscale.** Solo se añaden reglas en `DOCKER-USER`.

## 7. Diferencias menores con la guía del grupo

No requieren cambio, solo que todos usen el mismo dato:

- **Dirección del portal:** `Estudiante2.md` indica `10.10.0.6:8080` y la guía del grupo `10.10.0.9:8080`. El portal escucha en todas las interfaces, así que ambas funcionan; la bitácora de pruebas usa `10.10.0.9`.
- **Servicios deshabilitados al arranque:** es válido, pero hay que recordar iniciarlos antes de cada prueba. Si Squid está detenido con TPROXY activo, el tráfico web pasa sin filtrar en lugar de cortarse.

## 8. Al terminar

Informa al grupo de:

- si las reglas de `DOCKER-USER` fueron necesarias (sección 3.1);
- el resultado de la comprobación de origen conservado (sección 5);
- si se implementó o no el filtrado de HTTPS;
- los dos scripts de arranque y parada, subidos al repositorio.
