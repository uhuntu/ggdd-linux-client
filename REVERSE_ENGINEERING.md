# GGDD 4.9.1 Wine Bundle Analysis

## Conclusion

A Wine-free Linux client is feasible. The installed GGDD application is an Electron 37 application
based on Mihomo Party. Its vendor-specific network layer is included as readable TypeScript inside
`app.asar`, and the application already contains Linux-specific paths for API selection, Mihomo
startup, TUN authorization, and Unix-domain controller sockets.

The current Java application is only a controller UI. A complete port must also implement account
login, subscription refresh, profile generation, and native Mihomo lifecycle management.

## Current Runtime

1. `GGDD.exe` runs through Wine from the main `.wine-prefix`.
2. GGDD starts the bundled Windows `mihomo.exe`.
3. A local patch changes the controller transport from a Windows named pipe to TCP
   `127.0.0.1:19090`.
4. Mihomo exposes the proxy on `127.0.0.1:9674` and the controller on `127.0.0.1:19090`.
5. MetaCubeXD and `GgddLinuxClient` consume that controller API.

The static native Mihomo service on controller port `9090` is currently disabled and inactive.

## Confirmed Vendor Flow

### Login

- The renderer submits an email and password to the main process.
- The main process calls the vendor login endpoint through a generic gateway API.
- Request names and payloads are XOR transformed and base64 encoded.
- The returned authorization data is persisted in `user.yaml` using the same reversible encoding.

### Subscription Refresh

- The cached authorization value is sent to the subscription endpoint.
- The response contains an encrypted subscription URL.
- GGDD downloads that URL with vendor-specific headers.
- The response body is base64 encoded and XOR encrypted with a response-specific key supplied in
  an HTTP header.
- The resulting Mihomo YAML is encrypted again with GGDD's local static key and stored in
  `profiles/<id>.yaml`.

### Mihomo Startup

- GGDD generates an encrypted runtime configuration at `work/config.yaml`.
- It launches Mihomo with `--xor-config`, the static local key, a data directory, and an external
  controller argument.
- The upstream code already supports Linux by selecting a native executable and a Unix-domain
  controller socket.

## Reusable Components

- Native Linux `mihomo` binary already included in the bundle.
- GeoIP, geosite, ASN, country, and cache databases.
- Local MetaCubeXD assets.
- Vendor TypeScript API implementation from `app.asar`.
- Cross-platform profile generation and override logic.
- Existing account state can be migrated without asking for the password again, provided the
  cached authorization is still valid.

## Components That Must Change

- Replace Windows Electron packaging with a Linux Electron build or a native service/UI pair.
- Replace Windows system-proxy helper with Linux desktop proxy integration.
- Replace Windows sidecar path with the bundled native Linux Mihomo binary.
- Use a Unix-domain controller socket or a loopback TCP controller.
- Replace the Wine file locations with a normal Linux application data directory.
- Integrate the existing host TUN bridge or use Mihomo's native Linux TUN support directly.

## Risks

- The vendor can change API endpoints or encoding behavior in future releases.
- The service currently uses fallback API hosts, including plaintext HTTP endpoints.
- Cached account and profile files contain sensitive authorization and proxy data despite being
  reversibly encoded. They must be stored with user-only permissions.
- The current `apply-tes-tec-dns-fix.sh` reloads a static profile snapshot and can replace fresh
  subscription data.

## Recommended Implementation Stages

1. Build a local Node service that reads the existing cached account state and refreshes the
   subscription without starting Wine.
2. Download, decode, and validate the profile using native Linux Mihomo in test mode.
3. Start native Mihomo and expose the existing `9674` proxy and `19090` controller ports.
4. Extend the Java client with account status, refresh, connect/disconnect, and logs.
5. Add Linux system-proxy and TUN controls.
6. Retire Wine only after login, refresh, reconnect, reboot, and expiration handling are verified.

The first safe milestone is refresh-only operation using the existing cached login. It avoids
handling the user's password and can be tested while Wine remains available as a fallback.
