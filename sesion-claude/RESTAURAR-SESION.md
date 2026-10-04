# Restaurar la sesión de Claude Code en otro equipo

Esta guía está escrita para Claude Code en el equipo nuevo. El usuario trabajó este proyecto en otra máquina (Arch Linux) y se cambia a Debian; quiere continuar la misma conversación, con su memoria, sin volver a explicar nada.

Si el usuario te pide restaurar o actualizar la sesión, sigue los pasos de la sección 2. Si la sesión no se puede reanudar, la sección 4 resume el contexto necesario para continuar el trabajo igualmente.

## 1. Qué hay en esta carpeta

| Archivo | Qué es | A dónde va |
|---|---|---|
| `871ecf25-eda1-4f3f-872b-85d16556a090.jsonl` | Transcripción completa de la sesión | `~/.claude/projects/<proyecto>/` |
| `871ecf25-eda1-4f3f-872b-85d16556a090/` | Resultados de herramientas de la sesión (páginas del enunciado) | `~/.claude/projects/<proyecto>/` |
| `memory/` | Memoria persistente del proyecto (tres archivos) | `~/.claude/projects/<proyecto>/memory/` |
| `engram-p2redes.json` | Las 14 memorias de engram de este proyecto | Se importan con `engram import` |
| `archivos-locales/prompt-topologia-figma.md` | Archivo del proyecto que está excluido de git a propósito | Raíz del repositorio |
| `restaurar.sh` | Script que coloca todo lo anterior en su sitio | — |

`<proyecto>` es la ruta del repositorio con los caracteres no alfanuméricos cambiados por guiones. En el equipo original era `-home-alodev-Documents-p2redes`.

La transcripción es una copia tomada en el momento en que se creó esta carpeta. Los últimos mensajes de aquella conversación (el aviso de que la copia quedó subida) no están incluidos.

## 2. Pasos para restaurar

1. **Comprueba la ruta del repositorio.** Lo ideal es clonarlo en la misma ruta que en el equipo original, `/home/alodev/Documents/p2redes`, con el mismo usuario. Si la ruta es otra, el script ajusta la transcripción, pero ese caso no se ha probado.
2. **Ejecuta el script** desde la raíz del repositorio:

   ```bash
   bash sesion-claude/restaurar.sh
   ```

3. **Revisa la salida.** Debe terminar con "Restauración terminada" y mostrar el comando para continuar. Si engram no está instalado, el script lo avisa y sigue; las memorias de engram quedan sin importar, pero la sesión y la memoria de archivos sí se restauran.
4. **Indica al usuario cómo reanudar.** La sesión no se puede reanudar desde dentro de otra conversación: el usuario tiene que salir y ejecutar en una terminal:

   ```bash
   cd /home/alodev/Documents/p2redes && claude --resume 871ecf25-eda1-4f3f-872b-85d16556a090
   ```

5. **Configura el acceso a GitHub.** En el equipo original, git no tenía credenciales para HTTPS y cada `git push` se hacía con la sesión de `gh`. En el equipo nuevo basta con `gh auth login` y luego `gh auth setup-git`.

## 3. Si la sesión no se reanuda

Reanudar una sesión copiada de otro equipo no es un uso documentado de Claude Code y no se probó antes de crear esta carpeta. Puede fallar si la versión de Claude Code es distinta (la original era la 2.1.289) o si la ruta del proyecto no coincide.

Si `claude --resume` no la encuentra o da error, no insistas con la transcripción. Continúa con una sesión nueva usando:

- la memoria ya restaurada en `~/.claude/projects/<proyecto>/memory/`, que se carga sola;
- los documentos del repositorio, que son la fuente de verdad del proyecto;
- el resumen de la sección 4.

## 4. Contexto del proyecto

### Qué es

Proyecto final del curso Redes 2: **XelajuNetwork**, una red empresarial montada por cinco estudiantes, cada uno con un componente. El enunciado está en `Enunciado.pdf`. El usuario coordina la documentación común; el repositorio es `ALODEV-GT/firewallp2r2`, privado.

Cadena principal: ISP1/ISP2 → R-EDGE → FW → PROXY → R2 → SW1 → VLANs. La DMZ (VPN-SRV y WEB01) cuelga del firewall.

### Documentos

| Archivo | Contenido |
|---|---|
| `direccionamiento.md` | Fuente de verdad de direcciones, rutas y matriz de seguridad |
| `configuraciones.md` | Guía de configuración por componente, entorno, pruebas y pendientes por encargado (sección 10) |
| `bitacora-pruebas.md` | Las 107 pruebas a ejecutar, por fase, con columnas para estado y evidencia |
| `prompt-topologia-figma.md` | Prompt para generar el diagrama en Figma; excluido de git |

### Quién usa qué equipo

| Encargado | Componente | Equipo real |
|---|---|---|
| Estudiante 1 | R2, SW1, clientes, Zabbix, SRV01 | Anfitrión Ubuntu (autorizado por el catedrático) con QEMU/KVM y Open vSwitch |
| Estudiante 2 | PROXY | Equipo físico con Debian y NetworkManager |
| Estudiante 3 | R-EDGE | VM Debian en modo texto; los dos ISP son dos celulares por USB |
| Estudiante 4 | VPN-SRV, WEB01 | VM gestionadas con libvirt |
| Estudiante 5 | FW | Equipo físico con Debian en modo texto |

### Decisiones tomadas

- **Sin GNS3.** Solo máquinas virtuales QEMU o Debian instalado en modo texto.
- **Red interna en `10.10.0.0/16`.** Enlaces punto a punto en `/30`, cuatro VLAN, DMZ en `10.10.50.0/28`.
- **VPN.** VPN-ADMIN en `10.200.10.0/28` y VPN-USERS en `10.200.20.0/27`, con los peers que ya creó el encargado.
- **DHCP restringido en R2**, escuchando solo en `eth1.20`.
- **SW1 es un Open vSwitch** en el anfitrión del estudiante 1, con puertos tap y un puerto espejo `span0`.
- **Proxy con TPROXY y filtrado HTTPS por SNI**, sin descifrar. Necesita una caché DNS (`dnsmasq`) en PROXY compartida por los clientes y Squid; sin ella falla parte del HTTPS permitido.
- **Multi-WAN** con marcas de nftables, tablas de ruteo por ISP y un servicio de failover.

### Estado

- Las configuraciones se validaron en contenedores Debian 13 (sintaxis de nftables, Squid, dhcpd, Suricata, scripts; el proxy de extremo a extremo contra sitios reales; la lógica del Multi-WAN con interfaces simuladas).
- **No se ha probado nada en los equipos reales**, ni con cables ni con los celulares. El equipo está por empezar a configurar, siguiendo el orden de la sección 2.3 de `configuraciones.md` y registrando resultados en `bitacora-pruebas.md`.
- El encargado del proxy tiene montado un diseño distinto al de la guía (sin TPROXY ni HTTPS, y pidiendo que R2 redirija el puerto 80). Es una decisión abierta; la sección 10 de la guía dice qué cambia según lo que elija.

### Normas de trabajo acordadas con el usuario

- **Cada cambio acordado se escribe en los documentos, se confirma y se sube directo a `main`**, sin rama aparte y sin preguntar cada vez. Los commits siguen el formato convencional y no llevan atribución a la IA.
- **Los documentos del proyecto van en español.** Las respuestas al usuario, en español y breves.
- **Verificar antes de afirmar.** El usuario pide comprobar en los archivos antes de dar algo por cierto, y distinguir siempre lo probado de lo que no lo está.
- **`prompt-topologia-figma.md` se mantiene actualizado pero no se sube**, salvo la copia de esta carpeta.
- La carpeta `.atl/` sin seguimiento no es del proyecto; no se añade a los commits.

### Qué sigue

Cuando los encargados empiecen a configurar, llegarán errores y salidas de comandos. El trabajo esperado es diagnosticarlos, corregir la guía y la bitácora, y subir el cambio. También pueden llegar los datos reales que faltan: las redes de los dos celulares, los nombres de las interfaces de FW y la decisión del encargado del proxy.
