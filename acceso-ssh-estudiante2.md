# Acceso SSH temporal al PROXY desde el firewall

Guía para el estudiante 2 (PROXY). El objetivo es que el encargado del firewall (estudiante 5) pueda entrar por SSH al equipo del proxy, diagnosticar por qué no cruza el tráfico entre el firewall y R2, y aplicar los ajustes de `ajustes-estudiante2.md`.

El acceso es temporal: se crea un usuario aparte, solo entra con una clave, solo desde la IP del firewall (`10.10.0.5`), y se elimina al terminar (sección 5). Conviene que estés presente mientras se trabaja.

## 1. Qué se sabe del problema

| Comprobación | Resultado |
|---|---|
| Firewall → PROXY (`10.10.0.6` y `10.10.0.9`) | Responde |
| PROXY → R2 (`10.10.0.10`) | Responde |
| Firewall → R2 (`10.10.0.10`), a través del PROXY | No responde |
| Paquetes de R2 o de las VLAN vistos en el firewall | Ninguno |

Los dos enlaces funcionan por separado, así que el corte está en el reenvío dentro del equipo del proxy. La causa más probable es la cadena `FORWARD` de Docker, que descarta por defecto, o que `ip_forward` esté en `0`. No está confirmado; para eso es el acceso.

## 2. Pasos en el equipo del PROXY

Ejecuta todo con tu usuario, en este orden.

### 2.1 Instalar el servidor SSH

```bash
sudo apt update
sudo apt install -y openssh-server
```

### 2.2 Crear el usuario temporal

```bash
sudo adduser --disabled-password --gecos "" soporte-fw
```

El usuario no tiene contraseña, así que solo puede entrar con la clave del paso siguiente.

### 2.3 Autorizar la clave del firewall

```bash
sudo install -d -m 700 -o soporte-fw -g soporte-fw /home/soporte-fw/.ssh
echo 'from="10.10.0.5" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJihpjQ9+rliA3NsmAiJjbcnaobBNNKtCV07WqFVY9e firewall-xelajunetwork-acceso-temporal-proxy' | sudo tee /home/soporte-fw/.ssh/authorized_keys
sudo chown soporte-fw:soporte-fw /home/soporte-fw/.ssh/authorized_keys
sudo chmod 600 /home/soporte-fw/.ssh/authorized_keys
```

La clave es una sola línea; cópiala completa. El prefijo `from="10.10.0.5"` hace que solo sirva si la conexión viene del firewall.

### 2.4 Darle permisos de administrador

```bash
echo 'soporte-fw ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/soporte-fw
sudo chmod 440 /etc/sudoers.d/soporte-fw
sudo visudo -c
```

`visudo -c` debe terminar sin errores. Hace falta `NOPASSWD` porque el usuario no tiene contraseña.

### 2.5 Limitar quién puede entrar por SSH

El servidor SSH escucha en todas las interfaces del equipo, incluidos el Wi-Fi y Tailscale. Este archivo deja entrar únicamente al usuario temporal desde el firewall:

```bash
printf 'AllowUsers soporte-fw@10.10.0.5\nPasswordAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/xelajunetwork-acceso.conf
sudo sshd -t
```

`sshd -t` no debe mostrar nada. Si ya usabas SSH para entrar a este equipo con otro usuario, no crees este archivo, porque te dejaría fuera; avisa y se ajusta.

### 2.6 Iniciar el servicio

```bash
sudo systemctl restart ssh
sudo systemctl disable ssh
sudo ss -lntp | grep ':22 '
```

Debe aparecer `sshd` escuchando en el puerto 22. `disable` evita que arranque solo en el siguiente reinicio; el servicio sigue activo ahora.

### 2.7 Dejar conectados los enlaces del laboratorio

```bash
ip -br addr show enx9c69d3101d16
ping -c 2 10.10.0.5
```

La interfaz debe tener `10.10.0.6/30` y el ping debe responder.

## 3. Qué enviar al estudiante 5

1. La confirmación de que los pasos terminaron sin errores.
2. La huella del servidor, para comprobar que se conecta al equipo correcto:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

El firewall se conectará con:

```bash
ssh -i ~/.ssh/id_proxy_tmp soporte-fw@10.10.0.6
```

## 4. Qué se va a hacer dentro del equipo

Primero diagnosticar, sin cambiar nada:

- Estado de `ip_forward`, de la cadena `FORWARD` y de `DOCKER-USER`.
- Rutas, reglas de enrutamiento y tabla `xelajunetwork_proxy`.
- Qué servicio responde en el puerto 53 y en qué direcciones.
- Captura en las dos interfaces mientras el firewall hace ping a R2.

Después, corregir lo que el diagnóstico confirme. Lo previsto:

| Ajuste | Dónde |
|---|---|
| Activar el reenvío y permitirlo entre las dos interfaces del proyecto | `ip_forward` y cadena `DOCKER-USER` |
| Regla que entrega a Squid las respuestas de Internet (`socket transparent`) y exclusión de destinos internos | `/etc/nftables-xelajunetwork.nft` |
| Rutas para el tráfico de las VLAN y de Squid hacia el firewall | Tabla 101 y reglas `from <VLAN>` |
| Quitar `tcp_outgoing_address 10.10.0.6` | `/etc/squid/squid.conf` |
| Incluir todo lo anterior en los scripts | `xelajunetwork-tproxy-on` y `-off` |

Condiciones:

- Antes de editar un archivo se guarda una copia con la extensión `.antes-fw`.
- No se toca la configuración de Docker ni de Tailscale, ni `/etc/nftables.conf`, ni se ejecuta `nft flush ruleset`.
- No se añade NAT.
- Al terminar se entrega la lista de archivos cambiados y qué cambió en cada uno, para que actualices `Estudiante2.md`.

## 5. Retirar el acceso al terminar

```bash
sudo systemctl stop ssh
sudo deluser --remove-home soporte-fw
sudo rm /etc/sudoers.d/soporte-fw /etc/ssh/sshd_config.d/xelajunetwork-acceso.conf
```

Si no quieres conservar el servidor SSH:

```bash
sudo apt purge -y openssh-server
```

El estudiante 5 borra también su clave (`~/.ssh/id_proxy_tmp`) en el firewall.
