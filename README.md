# noctalia-niri-config-setup

niri config for the Noctalia v5 shell, with blur on all shell surfaces, apps and the overview.

## Install

```bash
mkdir -p ~/.config/niri
cp niri/config.kdl ~/.config/niri/config.kdl
niri validate
```

Requires a niri build with `background-effect` / `blur` support.
For lid-close lock, set `HandleLidSwitch=ignore` in `/etc/systemd/logind.conf`.
