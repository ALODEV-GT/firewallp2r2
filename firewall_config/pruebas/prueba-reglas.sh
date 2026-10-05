#!/bin/bash
# Simula los vecinos de FW en espacios de red y prueba el conjunto de reglas real.
S=$(cd "$(dirname "$0")" && pwd); W=enp3s0; I=enx00e04c360188; D=enx00e04c3604ff
for n in tfw tedge tpx tdmz; do ip netns del $n 2>/dev/null; ip netns add $n; ip -n $n link set lo up; done
F="ip netns exec tfw"
mk(){ ip link add zz$3 type veth peer name $3 netns $2; ip link set zz$3 netns tfw; ip -n tfw link set zz$3 name $1; }
mk $W tedge e0; mk $I tpx p0; mk $D tdmz d0
ip -n tfw link add wlp4s0 type dummy; ip -n tfw addr add 10.96.201.91/24 dev wlp4s0; ip -n tfw link set wlp4s0 up
ip -n tfw addr add 10.10.0.2/30 dev $W; ip -n tfw addr add 10.10.0.5/30 dev $I; ip -n tfw addr add 10.10.50.1/28 dev $D
for i in $W $I $D; do ip -n tfw link set $i up; done
ip -n tfw route add default via 10.96.201.68 dev wlp4s0
for r in 10.10.0.8/30 10.10.10.0/27 10.10.20.0/25 10.10.30.0/28 10.10.40.0/27; do ip -n tfw route add $r via 10.10.0.6; done
ip -n tfw route add 10.200.10.0/28 via 10.10.50.2; ip -n tfw route add 10.200.20.0/27 via 10.10.50.2
$F sysctl -qw net.ipv4.ip_forward=1
$F /usr/local/sbin/fw-rutas.sh
$F nft -f /etc/nftables.conf || { echo "NFT FALLÓ"; exit 1; }
# R-EDGE + "Internet"
ip -n tedge addr add 10.10.0.1/30 dev e0; ip -n tedge link set e0 up; ip -n tedge addr add 203.0.113.1/32 dev lo
ip -n tedge route add 10.10.0.0/16 via 10.10.0.2; ip -n tedge route add 10.200.0.0/16 via 10.10.0.2
# PROXY + equipos de las VLAN
ip -n tpx addr add 10.10.0.6/30 dev p0; ip -n tpx link set p0 up; ip -n tpx route add default via 10.10.0.5
for a in 10.10.10.10 10.10.20.10 10.10.30.2 10.10.40.10; do ip -n tpx addr add $a/32 dev lo; done
# DMZ: VPN-SRV, WEB01 y peers VPN
ip -n tdmz addr add 10.10.50.2/28 dev d0; ip -n tdmz addr add 10.10.50.10/28 dev d0; ip -n tdmz link set d0 up; ip -n tdmz route add default via 10.10.50.1
for a in 10.200.10.3 10.200.20.3; do ip -n tdmz addr add $a/32 dev lo; done
sleep 1
ok=0; bad=0
t(){ # ns proto src dst port esperado descripcion
  if [ "$2" = icmp ]; then ip netns exec $1 ping -c1 -W2 -I $3 $4 >/dev/null 2>&1 && r=PASA || r=BLOQ
  else r=$(ip netns exec $1 python3 $S/prueba-sonda.py $2 $3 $4 $5); fi
  if [ "$r" = "$6" ]; then ok=$((ok+1)); m=ok; else bad=$((bad+1)); m="** FALLA **"; fi
  printf '%-11s %-52s esperado=%s obtenido=%s\n' "$m" "$7" "$6" "$r"
}
INET=203.0.113.1
t tpx tcp 10.10.10.10 $INET 80  PASA "ADMIN -> Internet tcp/80"
t tpx tcp 10.10.20.10 $INET 443 PASA "USERS -> Internet tcp/443"
t tpx tcp 10.10.20.10 $INET 22  BLOQ "USERS -> Internet tcp/22"
t tpx tcp 10.10.40.10 $INET 80  PASA "SERVERS -> Internet tcp/80"
t tpx tcp 10.10.30.2  $INET 80  BLOQ "ZABBIX -> Internet tcp/80"
t tpx udp 10.10.0.6   $INET 53  PASA "PROXY -> Internet udp/53 (DNS)"
t tpx tcp 10.10.0.6   $INET 80  BLOQ "PROXY -> Internet tcp/80 (sin TPROXY)"
t tpx icmp 10.10.10.10 $INET 0  PASA "ADMIN -> Internet ping"
t tpx icmp 10.10.20.10 $INET 0  BLOQ "USERS -> Internet ping"
t tpx tcp 10.10.10.10 10.10.50.10 22 PASA "ADMIN -> WEB01 tcp/22"
t tpx icmp 10.10.10.10 10.10.50.10 0 PASA "ADMIN -> WEB01 ping"
t tpx tcp 10.10.20.10 10.10.50.10 80 PASA "USERS -> WEB01 tcp/80"
t tpx tcp 10.10.20.10 10.10.50.10 22 BLOQ "USERS -> WEB01 tcp/22"
t tpx tcp 10.10.20.10 10.10.50.2  80 BLOQ "USERS -> VPN-SRV tcp/80"
t tdmz tcp 10.10.50.10 $INET 443 PASA "WEB01 -> Internet tcp/443 (ngrok)"
t tdmz tcp 10.10.50.10 $INET 80  BLOQ "WEB01 -> Internet tcp/80"
t tdmz icmp 10.10.50.10 10.10.10.10 0 BLOQ "WEB01 -> VLAN ADMIN ping"
t tdmz tcp 10.10.50.10 10.10.40.10 80 BLOQ "WEB01 -> VLAN SERVERS tcp/80"
t tdmz tcp 10.200.10.3 10.10.10.10 22 PASA "VPN-ADMIN -> VLAN ADMIN tcp/22"
t tdmz icmp 10.200.10.3 10.10.20.10 0 PASA "VPN-ADMIN -> VLAN USERS ping"
t tdmz tcp 10.200.10.3 10.10.30.2 80  PASA "VPN-ADMIN -> ZABBIX tcp/80"
t tdmz tcp 10.200.10.3 10.10.30.2 22  BLOQ "VPN-ADMIN -> ZABBIX tcp/22"
t tdmz icmp 10.200.20.3 10.10.10.10 0 BLOQ "VPN-USERS -> VLAN ADMIN ping"
t tdmz tcp 10.200.20.3 10.10.40.10 80 PASA "VPN-USERS -> SERVERS tcp/80"
t tdmz tcp 10.200.20.3 10.10.40.10 22 BLOQ "VPN-USERS -> SERVERS tcp/22"
t tdmz icmp 10.200.20.3 10.10.20.10 0 PASA "VPN-USERS -> VLAN USERS ping"
t tdmz tcp 10.200.20.3 10.10.30.2 80  BLOQ "VPN-USERS -> ZABBIX tcp/80"
t tdmz tcp 10.200.20.3 $INET 443 PASA "VPN-USERS -> Internet tcp/443 (full tunnel)"
t tdmz tcp 10.200.20.3 $INET 22  BLOQ "VPN-USERS -> Internet tcp/22"
t tedge udp 203.0.113.1 10.10.50.2 51820 PASA "Internet -> VPN-SRV udp/51820"
t tedge tcp 203.0.113.1 10.10.50.10 80 BLOQ "Internet -> WEB01 tcp/80"
t tedge tcp 203.0.113.1 10.10.10.10 22 BLOQ "Internet -> VLAN ADMIN tcp/22"
t tpx tcp 10.10.30.2 10.10.0.1 10050 PASA "ZABBIX -> R-EDGE tcp/10050"
t tedge tcp 10.10.0.1 10.10.30.2 10051 PASA "R-EDGE -> ZABBIX tcp/10051"
t tpx icmp 10.10.10.10 10.10.0.5 0 PASA "ADMIN -> FW ping"
t tpx tcp 10.10.10.10 10.10.0.5 22 PASA "ADMIN -> FW tcp/22"
t tpx icmp 10.10.20.10 10.10.0.5 0 BLOQ "USERS -> FW ping"
t tpx tcp 10.10.20.10 10.10.0.5 22 BLOQ "USERS -> FW tcp/22"
t tpx icmp 10.10.0.6 10.10.0.5 0 PASA "PROXY (vecino) -> FW ping"
t tedge icmp 10.10.0.1 10.10.0.2 0 PASA "R-EDGE (vecino) -> FW ping"
t tedge tcp 203.0.113.1 10.10.0.2 22 BLOQ "Internet -> FW tcp/22"
echo "RESULTADO: $ok correctas, $bad fallas"
echo "--- salida del trafico reenviado (debe ser enp3s0, no la Wi-Fi):"; $F ip route get 203.0.113.1 from 10.10.10.10 iif $I | head -1
echo "--- trafico propio del equipo (debe ser la Wi-Fi):"; $F ip route get 203.0.113.1 | head -1
for n in tfw tedge tpx tdmz; do ip netns del $n; done
