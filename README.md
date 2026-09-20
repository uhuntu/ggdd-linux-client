# GGDD Linux Client

This is a lightweight Linux front end for GGDD. It replaces the Electron UI with Java/Swing,
refreshes the subscription directly from GGDD using the existing cached login, and displays every
selector and node through the Mihomo controller API.

GGDD's servers require behavior provided by its customized Windows Mihomo sidecar. Stock Linux
Mihomo accepts the same profile but the remote servers close its connections. The launcher
therefore uses Wine only for that vendor core; the GGDD Electron application does not need to be
running.

This is the only supported way to run GGDD on this machine. The older ways (the Wine GGDD app on
`9674`/`19090`, the Waydroid APK on `10808`, the TUN bridge, and the static YAML snapshots) were
retired on 2026-09-20 and moved to `~/tools/ggdd-archive-20260920/` (see its `MANIFEST.txt`).

## Persistent core (systemd)

The proxy runs as a user service, independent of the UI window:

```sh
systemctl --user status ggdd-core      # proxy 127.0.0.1:19674, controller 127.0.0.1:19091
systemctl --user restart ggdd-core     # re-fetches the subscription, then restarts the core
journalctl --user -u ggdd-core -f
```

It is enabled at login. Privoxy (`127.0.0.1:8118`, used by shell `HTTP_PROXY`, `ssh 149proxy` and
others) forwards to `127.0.0.1:19674`. MetaCubeXD can use `http://127.0.0.1:19091` as its API address.

## UI

```sh
./run-ggdd-linux-client.sh
```

The launcher reuses the service's core if it is running. Otherwise it:

1. Refreshes and validates the cached GGDD subscription.
2. Generates a user-only encrypted runtime profile.
3. Starts the vendor core on proxy `127.0.0.1:19674` and controller `127.0.0.1:19091`.
4. Opens the Java UI and stops that core when the UI exits.

Still required from the old bundle in `~/tools/ggdd-linux-wine-dashboard-bundle/`: the main
`ggdd-full-wine-bundle/.wine-prefix` (vendor sidecar and cached login), `data/` (geodata) and the
native `mihomo`. If the login expires, run `ggdd-full-wine-bundle/run-ggdd.sh` once to sign in again.

Headless controller check:

```sh
./run-ggdd-linux-client.sh --list
```

## Export to Clash

The **Export Clash YAML** button (bottom right) saves the cached subscription profile
(`runtime/profile.yaml`, refreshed whenever the core service restarts) as a Clash/Mihomo YAML.
The export drops this machine's `interface-name` and sets `allow-lan: false` /
`bind-address: '127.0.0.1'`; proxies, groups and rules are unchanged. The file is written with
mode `0600` and contains your proxy credentials, so keep it private.

From a terminal (no display needed):

```sh
java -cp . GgddLinuxClient --export ~/ggdd-clash.yaml
```

GGDD's servers only accept GGDD's customized core, so a stock Clash/Mihomo core may connect but
have its connections closed even though the YAML imports and validates cleanly.

## Native refresh prototype

The native refresher reuses the existing GGDD Wine login cache. It does not ask for or print the
account password, authorization token, or subscription URL.

```sh
./ggdd-native-refresh.mjs status
./refresh-native-profile.sh
./ggdd-native-refresh.mjs prepare-test
```

`refresh-native-profile.sh` fetches the current GGDD subscription, decodes it into
`runtime/profile.yaml`, sets user-only permissions, and validates it with the bundled native Linux
Mihomo. The `runtime/` directory contains sensitive proxy configuration and is excluded from source
control.

`prepare-test` creates `runtime/native-test.yaml` using isolated ports:

- Mixed proxy: `127.0.0.1:19674`
- Controller: `127.0.0.1:19091`

Runtime profiles contain proxy credentials, are mode `0600`, and are ignored by source control.
