#!/usr/bin/env bash
# Post-boot check that the GGDD core, timer and tunnels came up on their own. Exit 0 = all pass.
cd "$(dirname "$0")"
pass=0 fail=0
ok()  { echo "PASS  $*"; pass=$((pass + 1)); }
bad() { echo "FAIL  $*"; fail=$((fail + 1)); }
info() { echo "      $*"; }
check() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what"; fi; }
sctl() { systemctl --user "$@"; }

echo "== GGDD autostart check $(date '+%F %T')  boot: $(uptime -s)  ($(uptime -p))"

marker=runtime/.pre-reboot-boot-id
if [[ -f $marker ]]; then
  if [[ "$(cat /proc/sys/kernel/random/boot_id)" != "$(cat "$marker")" ]]; then
    ok "machine rebooted since the marker was written"
  else
    bad "no reboot since the marker was written (same boot id)"
  fi
fi

check "linger enabled (user services start without logging in)" [ "$(loginctl show-user "$USER" -p Linger --value)" = yes ]

check "ggdd-core.service enabled" sctl is-enabled ggdd-core.service
for _ in {1..60}; do sctl is-active --quiet ggdd-core.service && break; sleep 2; done
check "ggdd-core.service active" sctl is-active --quiet ggdd-core.service
info "started: $(sctl show ggdd-core.service -p ActiveEnterTimestamp --value)  restarts: $(sctl show ggdd-core.service -p NRestarts --value)"

up=0
for _ in {1..60}; do
  curl -fsS --max-time 2 http://127.0.0.1:19091/version >/dev/null 2>&1 && { up=1; break; }
  sleep 2
done
[[ $up == 1 ]] && ok "controller answers on 127.0.0.1:19091" || bad "controller did not answer on 127.0.0.1:19091 within 120s"

egress=""
for _ in {1..10}; do
  egress=$(curl -fsS --max-time 15 --proxy socks5h://127.0.0.1:19674 https://api.ipify.org 2>/dev/null) && break
  egress=""; sleep 3
done
[[ -n $egress ]] && ok "proxy 127.0.0.1:19674 reaches the internet (exit IP $egress)" || bad "proxy 127.0.0.1:19674 has no internet"

nodes=$(curl -fsS --max-time 3 http://127.0.0.1:19091/proxies 2>/dev/null | python3 -c 'import sys,json; p=json.load(sys.stdin)["proxies"]; print(sum(len(v["all"]) for k,v in p.items() if k=="GGDD"))' 2>/dev/null)
[[ ${nodes:-0} -gt 0 ]] && ok "GGDD group loaded ($nodes nodes)" || bad "GGDD group has no nodes"

check "ggdd-core-refresh.timer enabled and active" bash -c 'systemctl --user is-enabled ggdd-core-refresh.timer && systemctl --user is-active ggdd-core-refresh.timer'
info "next refresh: $(sctl show ggdd-core-refresh.timer -p NextElapseUSecRealtime --value)"

for u in reverse-149 reverse-241; do check "$u.service active" sctl is-active --quiet "$u.service"; done

check "privoxy stays off" bash -c '! systemctl is-active --quiet privoxy && ! ss -ltn | grep -q ":8118 "'

echo "== $pass passed, $fail failed"
[[ $fail == 0 ]]
