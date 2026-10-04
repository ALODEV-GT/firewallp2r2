---
name: commit-and-push-to-main
description: "In p2redes, every change must be reflected in the project docs, committed and pushed straight to main"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 871ecf25-eda1-4f3f-872b-85d16556a090
  modified: 2026-10-04T19:45:56.216Z
---

In the p2redes repo (remote `ALODEV-GT/firewallp2r2`), every change we make to the project must be written into the documents and then committed and pushed directly to `main`, without asking each time and without a separate branch.

**Why:** The user said on 2026-10-04: "todos los cambios que vayamos haciendo, es necesario actualizar los archivos y subirlos a main." This came right after I pushed to a feature branch instead of main and they had to ask for the merge and the branch deletion.

**How to apply:** After any agreed change, update all affected docs (`configuraciones.md`, `direccionamiento.md`, and the git-excluded `prompt-topologia-figma.md`), then commit with a conventional commit message (no AI attribution) and push to `origin main`. Git has no HTTPS credential helper configured, so push with `git -c credential.helper='!gh auth git-credential' push origin main`. My interpretation: this covers documentation changes in this repo only; it is not a go-ahead for force pushes, history rewrites or deletions. Leave the untracked `.atl/` folder out of commits. See [[no-gns3-qemu-only]].
