---
name: no-gns3-qemu-only
description: p2redes (XelajuNetwork) must not use GNS3; only QEMU VMs or Debian installed in text mode as the main OS
metadata:
  node_type: memory
  type: project
  originSessionId: 871ecf25-eda1-4f3f-872b-85d16556a090
  modified: 2026-10-04T03:06:01.576Z
---

The Redes 2 final project (XelajuNetwork) must not use GNS3. Nodes are QEMU virtual machines or physical machines with Debian installed in text mode as the main OS. VMs are interconnected with Linux bridges on the host.

**Why:** The user stated this on 2026-10-03 after I wrote the config guide assuming GNS3 (an earlier session had prepared a Debian image as a GNS3 QEMU template). The project statement itself only names QEMU, virtual interfaces and bridges.

**How to apply:** Do not propose GNS3 nodes (NAT, Cloud, built-in switch) or GNS3 link actions in any doc or instruction for this project. Use host bridges + tap interfaces and plain `qemu-system-x86_64` commands instead.
