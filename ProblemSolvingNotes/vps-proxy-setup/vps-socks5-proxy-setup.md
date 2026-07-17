# VPS SOCKS5 Proxy Setup and Port Testing Guide

This guide documents a working setup for a SOCKS5 proxy on an Ubuntu VPS using 3proxy, along with commands to verify that the proxy works and to test SMTP ports 25 and 587. The proxy service can run correctly even when SMTP ports are blocked by the VPS provider.[cite:18][cite:76]

## What this guide does

It installs and configures 3proxy on a fresh Ubuntu VPS, binds a SOCKS5 listener to the VPS public IPv4 address, enables startup with systemd, opens the proxy port in UFW, and provides test commands for general proxy traffic and SMTP reachability.[cite:18][cite:97] Port 25 and sometimes 587 may still be blocked upstream by the VPS provider even after local firewall rules are opened.[cite:65][cite:76]

## Server values used in this setup

Use these values exactly as shown unless they need to be changed:

- VPS IP: `VPS_IP`
- Proxy port: `1080`
- Proxy username: `PROXY_USER`
- Proxy password: `PROXY_PASS`
- SSH port: `22`

## Step 1: Connect to the VPS

```bash
ssh root@VPS_IP
```

## Step 2: Install and configure 3proxy

Save the following script on the VPS as `setup-3proxy.sh`:

```bash
#!/bin/bash
set -euo pipefail

PROXY_PORT=1080
SSH_PORT=22
PROXY_USER="PROXY_USER"
PROXY_PASS="PROXY_PASS"

IPS=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1)
[ -n "$IPS" ] || { echo "No IPv4 addresses found"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y build-essential wget tar curl ufw

cd /tmp
rm -rf /tmp/3proxy-* /tmp/3proxy.tar.gz
V=0.9.5
wget -qO 3proxy.tar.gz "https://github.com/3proxy/3proxy/archive/refs/tags/$V.tar.gz"
tar -xzf 3proxy.tar.gz
cd "3proxy-$V"
make -f Makefile.Linux
mkdir -p /etc/3proxy /var/log/3proxy
cp bin/3proxy /usr/local/bin/3proxy

{
  echo maxconn 300
  echo "nserver 1.1.1.1"
  echo "nserver 8.8.8.8"
  echo nscache 65536
  echo "timeouts 1 5 30 60 180 1800 15 60"
  echo "log /var/log/3proxy/3proxy.log D"
  echo rotate 7
  echo "users $PROXY_USER:CL:$PROXY_PASS"
  echo "auth strong"
  echo "allow $PROXY_USER"
  PORT=$PROXY_PORT
  for IP in $IPS; do
    echo "socks -p$PORT -i$IP -e$IP"
    PORT=$((PORT+1))
  done
} > /etc/3proxy/3proxy.cfg

cat > /etc/systemd/system/3proxy.service <<'UNIT'
[Unit]
Description=3proxy SOCKS5
After=network.target

[Service]
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

ufw allow "$SSH_PORT/tcp"
IPCOUNT=$(printf '%s\n' "$IPS" | grep -c .)
for p in $(seq "$PROXY_PORT" $((PROXY_PORT + IPCOUNT - 1))); do
  ufw allow "$p/tcp"
done
ufw --force enable

echo ""
echo "=========================================="
echo " SOCKS5 ready on server IP(s):"
PORT=$PROXY_PORT
for IP in $IPS; do
  echo " socks5://$PROXY_USER:$PROXY_PASS@$IP:$PORT"
  PORT=$((PORT+1))
done
echo "=========================================="
```

Make it executable and run it:

```bash
chmod +x setup-3proxy.sh
./setup-3proxy.sh
```

## Step 3: Important fix for systemd

If `systemctl status 3proxy` shows repeated restarts or `start-limit-hit`, remove `daemon` from `/etc/3proxy/3proxy.cfg`. Running 3proxy in daemon mode can cause systemd to think the process exited successfully and restart it repeatedly.[cite:38][cite:41]

Use:

```bash
vim /etc/3proxy/3proxy.cfg
systemctl reset-failed 3proxy
systemctl daemon-reload
systemctl restart 3proxy
```

The working state should look like this:

```bash
systemctl status 3proxy --no-pager
ss -tlnp | grep 3proxy
```

Expected result:

- `3proxy.service` is `active (running)`
- `ss` shows `VPS_IP:1080` listening

A foreground systemd service with a listening socket confirms that the SOCKS5 service itself is running correctly.[cite:38][cite:42]

## Step 4: Manual service checks on the VPS

Run these commands to confirm the service is healthy:

```bash
systemctl status 3proxy --no-pager
ss -tlnp | grep 3proxy
journalctl -u 3proxy -n 50 --no-pager
cat /etc/3proxy/3proxy.cfg
```

These commands verify service state, listening ports, recent logs, and the generated configuration.[cite:18][cite:97]

## Step 5: Test the proxy from another machine

Run this from the client machine, not the VPS:

```bash
curl -v --max-time 15 --socks5-hostname "PROXY_USER:PROXY_PASS@VPS_IP:1080" https://api.ipify.org
```

A successful result should return `VPS_IP`, which proves that traffic is leaving through the VPS and that hostname resolution is going through the SOCKS5 proxy.[cite:52][cite:61]

## Step 6: Single-proxy health check script

Save this on the client machine as `check-proxy.sh`:

```bash
#!/bin/bash
# Проверка SOCKS5 прокси: живость + IP + гео + порт 25
# Запуск: bash check-proxy.sh

set -u

PROXY_HOST="VPS_IP"
PROXY_PORT="1080"
PROXY_USER="PROXY_USER"
PROXY_PASS="PROXY_PASS"

SMTP_HOST="gmail-smtp-in.l.google.com"

AUTH="${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}"
SHORT="${PROXY_HOST}:${PROXY_PORT}"

printf "%-22s %-6s %-16s %-7s %s\n" "PROXY" "LIVE" "EXIT_IP" "PORT25" "GEO"

IP=$(curl -s --max-time 15 --socks5-hostname "$AUTH" https://api.ipify.org)

if [ -z "$IP" ]; then
  printf "%-22s %-6s %-16s %-7s %s\n" "$SHORT" "DEAD" "-" "-" "-"
  exit 1
fi

GEO=$(curl -s --max-time 15 --socks5-hostname "$AUTH" https://ipinfo.io/country)
[ -z "$GEO" ] && GEO="?"

if curl -s --max-time 15 --socks5-hostname "$AUTH" "telnet://$SMTP_HOST:25" </dev/null >/dev/null 2>&1; then
  P25="OPEN"
else
  P25="BLOCK"
fi

printf "%-22s %-6s %-16s %-7s %s\n" "$SHORT" "OK" "$IP" "$P25" "$GEO"
```

Run it:

```bash
chmod +x check-proxy.sh
./check-proxy.sh
```

A result like the following means the proxy works but port 25 is blocked:

```text
PROXY                  LIVE   EXIT_IP          PORT25  GEO
VPS_IP:1080   OK     VPS_IP  BLOCK   US
```

That means the SOCKS5 proxy is healthy even if SMTP egress is not.[cite:22][cite:60]

## Step 7: Open ports in UFW

On the VPS, open the ports locally:

```bash
ufw allow 25/tcp
ufw allow 587/tcp
ufw status verbose
```

This only changes the VPS firewall and does not override provider-level SMTP filtering.[cite:67][cite:69]

## Step 8: Test SMTP connectivity from the VPS

Use timeouts so tests do not hang indefinitely:

```bash
nc -vz -w 5 gmail-smtp-in.l.google.com 25
nc -vz -w 5 smtp.gmail.com 587
```

If both commands time out, the most likely cause is outbound SMTP filtering by the VPS provider rather than a problem in Ubuntu or 3proxy.[cite:76][cite:79]

## Step 9: Test SMTP connectivity through the proxy

From the client machine:

```bash
curl -v --max-time 15 --socks5-hostname "PROXY_USER:PROXY_PASS@VPS_IP:1080" "telnet://gmail-smtp-in.l.google.com:25" </dev/null
curl -v --max-time 15 --socks5-hostname "PROXY_USER:PROXY_PASS@VPS_IP:1080" "telnet://smtp.gmail.com:587" </dev/null
```

If these time out or fail while regular HTTPS proxy traffic works, the SMTP block is upstream and not a SOCKS5 configuration failure.[cite:22][cite:33]

## Step 10: Interpret the results

| Result | Meaning |
|---|---|
| `systemctl status 3proxy` is active and `ss` shows port 1080 listening | Proxy service is running correctly.[cite:38][cite:42] |
| `curl --socks5-hostname ... https://api.ipify.org` returns `VPS_IP` | Proxy authentication and traffic forwarding are working.[cite:52][cite:60] |
| Port 25 says `BLOCK` but IP test succeeds | SOCKS5 proxy is healthy, but SMTP/25 is blocked upstream.[cite:76][cite:79] |
| Port 587 also times out | Provider may be filtering SMTP broadly, not just port 25.[cite:65][cite:79] |

## Common problems and fixes

### 3proxy service exits immediately

Cause: `daemon` in the config while systemd expects a foreground process.[cite:41][cite:43]

Fix:

- Remove `daemon` from `/etc/3proxy/3proxy.cfg`
- Run:

```bash
systemctl reset-failed 3proxy
systemctl daemon-reload
systemctl restart 3proxy
```

### Proxy port not listening

Check:

```bash
ss -tlnp | grep 3proxy
journalctl -u 3proxy -n 50 --no-pager
```

Possible causes include bad config syntax, wrong bind IP, or a malformed port line in `3proxy.cfg`.[cite:18][cite:41]

### SMTP stays blocked after opening UFW

Cause: provider-level outbound SMTP block.[cite:76][cite:78]

Fix options:

- Ask the VPS provider to unblock outbound SMTP
- Use port 587 with an authenticated SMTP relay if allowed
- Use a smarthost or mail relay service instead of direct SMTP on port 25.[cite:79][cite:87]

## Minimal command summary

### On the VPS

```bash
systemctl status 3proxy --no-pager
ss -tlnp | grep 3proxy
ufw allow 25/tcp
ufw allow 587/tcp
nc -vz -w 5 gmail-smtp-in.l.google.com 25
nc -vz -w 5 smtp.gmail.com 587
```

### On the client machine

```bash
curl -v --max-time 15 --socks5-hostname "PROXY_USER:PROXY_PASS@VPS_IP:1080" https://api.ipify.org
curl -v --max-time 15 --socks5-hostname "PROXY_USER:PROXY_PASS@VPS_IP:1080" "telnet://gmail-smtp-in.l.google.com:25" </dev/null
curl -v --max-time 15 --socks5-hostname "PROXY_USER:PROXY_PASS@VPS_IP:1080" "telnet://smtp.gmail.com:587" </dev/null
```

## Final notes

A successful `api.ipify.org` test is the strongest practical proof that the SOCKS5 proxy is working.[cite:52][cite:60] Failure on ports 25 or 587 after that usually points to VPS-provider SMTP restrictions, not a broken 3proxy installation.[cite:76][cite:79]
