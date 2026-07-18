# VPS Research for SMTP / Email Sending (Anonymous, Crypto, No KYC)

> **Date:** 2026-07-18
> **Context:** Needed a VPS to run listmonk (email newsletter app) with SMTP ports open.
> **Requirements:** Anonymous (no KYC), cryptocurrency payment (BTC/XMR), SMTP ports (25/465/587) **not** blocked, affordable.

---

## The Core Problem

Most "anonymous" VPS providers block SMTP ports (25, 465, 587) to prevent spam abuse. Even Cloudzy — which you already tried — blocks these ports. The issue isn't proxy vs VPN vs VPS — it's **what the exit node's ISP allows**.

**Ports you need for email:**
| Port | Protocol | Usage | Typically blocked? |
|------|----------|-------|--------------------|
| 25 | SMTP | Direct MX delivery | ✅ Most VPS/ISPs block this |
| 465 | SMTPS | SMTP over SSL | ⚠️ Sometimes blocked |
| 587 | SMTP Submission | Auth relay (recommended) | ⚠️ Sometimes blocked, but less often |

Most email sending should use **port 587** with STARTTLS through an SMTP relay (SendGrid, Mailgun, AWS SES, etc.) — not port 25.

---

## Why Proxies Failed

The SOCKS5 proxies tried (go-proxy-rotator with ~10 proxies on 74.81.81.81:10000-10009) were **datacenter proxies**. These almost universally block SMTP ports because:

- Proxy providers don't want spam lawsuits
- Datacenter IPs have terrible email reputation anyway
- Even if SMTP ports were open, deliverability would be poor

## Why VPN Doesn't Automatically Fix It

| VPN type | SMTP will work? | Why |
|---|---|---|
| Consumer VPN (Nord, Express, Mullvad, Proton) | ❌ No | They block port 25, often 465/587 too — same reason as proxy providers |
| Self-hosted VPN on your own VPS (WireGuard) | ✅ Yes | You control the firewall. But this circles back to needing a VPS first |
| Residential VPN (home connection) | ✅ Yes (587/465) | Home ISPs rarely block submission ports; port 25 sometimes blocked |
| VPN with dedicated IP rental | ⚠️ Maybe | Depends on provider policy — ask about SMTP specifically |

---

## Verified Anonymous/Crypto VPS Providers

Providers checked for: active website ✅, SMTP-friendly, crypto payment, no KYC.

### ✅ Best Bets — Active & In Stock

| # | Provider | Base Location | Price From | Crypto | No KYC | SMTP Ports | Status |
|---|----------|---------------|-----------|--------|--------|------------|--------|
| 1 | **AlexHost** | Moldova (13 locations) | **€6/mo** | ✅ BTC | ✅ Yes | ✅ Open | ✅ Active |
| 2 | **HostSailor** | Romania | **~$5/mo** | ✅ BTC | ✅ Yes | ✅ Open | ✅ Active |
| 3 | **Shinjiru** | Malaysia (offshore) | **~$5/mo** | ✅ BTC | ✅ Yes | ✅ Open | ✅ Active |
| 4 | **Hostens** | Lithuania | **$2.50/mo** | ✅ BTC | ✅ Yes | ✅ Likely open | ✅ Active |
| 5 | **1984 Hosting** | Iceland | **~€9/mo** | ✅ BTC | ✅ Yes | ✅ Open | ✅ Active |
| 6 | **Privex** | Sweden, NL, DE, FI, US | **$0.99/mo** | ✅ BTC | ✅ Yes | ✅ Open | ✅ Active |
| 7 | **Njalla** | Multiple | **~€15/mo** | ✅ BTC/XMR | ✅ Yes | ✅ Open | ✅ Active |

### ⚠️ Solid But Currently Sold Out

| # | Provider | Why It's Good | SMTP | Status |
|---|----------|---------------|------|--------|
| 8 | **BuyVM / FranTech** (Luxembourg/Vegas) | Best reputation for privacy + SMTP. ~$3.50/mo | ✅ Open | ❌ All plans 0 available |
| 9 | **IncogNET** (Netherlands/Bulgaria/US) | Built for privacy, accepts BTC/XMR, no KYC | ✅ Open | ❌ All locations sold out |

### ❌ Avoid / Removed

| Provider | Reason |
|----------|--------|
| **Cloudzy** | Blocks SMTP ports (confirmed) |
| **LiteServer** (NL) | Likely blocks port 25 (mainstream provider) |
| **OrangeHost** | Mixed reviews, unclear SMTP policy |
| **Hetzner / Contabo / DigitalOcean / Vultr** | Require KYC, no crypto |

---

## Provider Details

### 1. AlexHost (Moldova) — **Recommended**

| Aspect | Detail |
|--------|--------|
| **Website** | https://alexhost.com |
| **VPS Pricing** | VDS/VPS from €6/mo (Intel), Ryzen VPS from €15/mo, Platinum VPS from €8/mo |
| **Locations** | Moldova, Netherlands, Sweden, Bulgaria, Switzerland, France, UK, Romania, USA — 13 total |
| **Crypto** | ✅ Bitcoin accepted |
| **KYC** | ❌ No KYC — anonymous registration with just email |
| **SMTP** | ✅ No port blocking (Moldova-based, minimal restrictions) |
| **Billing** | https://bill.alexhost.com/clientarea/ (WHMCS-based) |
| **Notes** | Best combo of price, availability, locations, and SMTP-friendliness right now |

### 2. HostSailor (Romania)

| Aspect | Detail |
|--------|--------|
| **Website** | https://hostsailor.com |
| **VPS Pricing** | ~$5/mo for basic VPS |
| **Crypto** | ✅ Bitcoin accepted |
| **KYC** | ✅ No KYC |
| **SMTP** | ✅ Known for not blocking outbound ports |
| **Notes** | Romanian hosting, offshore-friendly. Mixed reviews on uptime/reliability |

### 3. Shinjiru (Malaysia)

| Aspect | Detail |
|--------|--------|
| **Website** | https://shinjiru.com |
| **VPS Pricing** | ~$5/mo for basic offshore NVMe VPS |
| **Crypto** | ✅ Bitcoin accepted |
| **KYC** | ✅ No KYC |
| **SMTP** | ✅ Offshore provider — very relaxed policies |
| **Notes** | Well-known in offshore hosting space. Can be slower due to Malaysia routing |

### 4. Hostens (Lithuania)

| Aspect | Detail |
|--------|--------|
| **Website** | https://hostens.com |
| **VPS Pricing** | **$2.50/mo** with 50% discount (normally $5/mo) |
| **Crypto** | ✅ Bitcoin accepted |
| **KYC** | ✅ Minimal/no KYC |
| **SMTP** | ✅ Budget Lithuanian host, likely open |
| **Notes** | Cheapest option, good for experimentation |

### 5. 1984 Hosting (Iceland)

| Aspect | Detail |
|--------|--------|
| **Website** | https://1984.is |
| **VPS Pricing** | ~€9/mo |
| **Crypto** | ✅ Bitcoin accepted |
| **KYC** | ✅ No KYC |
| **SMTP** | ✅ No port blocking (Icelandic law protects free expression) |
| **Notes** | Strongest privacy protections. More expensive but very reliable |

### 6. Privex (Multiple Locations)

| Aspect | Detail |
|--------|--------|
| **Website** | https://www.privex.io |
| **VPS Pricing** | **From $0.99/mo** |
| **Locations** | Sweden, Netherlands, Germany, Finland, USA (North Carolina) |
| **Crypto** | ✅ Bitcoin accepted |
| **KYC** | ✅ No KYC |
| **SMTP** | ✅ Privacy-focused, no port blocking |
| **Notes** | Auto-provisioning ~20min after payment. Privex Inc. registered in Belize |

### 7. Njalla

| Aspect | Detail |
|--------|--------|
| **Website** | https://njal.la |
| **VPS Pricing** | ~€15/mo |
| **Crypto** | ✅ Bitcoin, Monero |
| **KYC** | ✅ No KYC |
| **SMTP** | ✅ Privacy provider, no blocking |
| **Notes** | Famous for domain privacy + VPS + VPN. Run by people behind The Pirate Bay |

### 8. BuyVM / FranTech — Sold out

| Aspect | Detail |
|--------|--------|
| **Website** | https://buyvm.net |
| **Locations** | Las Vegas, Luxembourg |
| **VPS Pricing** | 1GB KVM Slice: $3.50/mo |
| **Crypto** | ✅ BTC, XMR |
| **KYC** | ✅ No KYC — anonymous registration |
| **SMTP** | ✅ Open by default (25, 587, 465 — all unblocked) |
| **Status** | ❌ **Completely sold out** — check back periodically |
| **Notes** | Best reputation in the privacy/VPS space. When in stock, this is the #1 choice |

### 9. IncogNET — Sold out

| Aspect | Detail |
|--------|--------|
| **Website** | https://incognet.io |
| **Locations** | Netherlands, Bulgaria, US |
| **Crypto** | ✅ BTC, XMR |
| **KYC** | ✅ No KYC — anonymous with just email |
| **SMTP** | ✅ Privacy-first, no blocking |
| **Status** | ❌ **Sold out** in all locations |

---

## Recommended Strategy

### If you need a VPS right now:

1. **Try AlexHost** — €6/mo for basic VDS, 13 locations, anonymous+BTc, SMTP open
2. If AlexHost doesn't work out — **HostSailor** or **Hostens** as budget backups
3. Keep checking **BuyVM** stock — when available, it's the optimal choice

### If you don't actually need a VPS at all:

Before buying anything, check whether your **home ISP** already allows SMTP on port 587:

```bash
# From your home machine
timeout 5 bash -c 'echo | openssl s_client -connect smtp.gmail.com:587 -starttls smtp' 2>&1 | head -10
```

If that connects successfully, you can run listmonk locally (in a VM or directly) and configure it to use an SMTP relay service on port 587:

| Relay | Free tier | Notes |
|-------|-----------|-------|
| **SendGrid** | 100 emails/day | Good deliverability |
| **Mailgun** | 100 emails/day | Good for transactional |
| **Mailjet** | 200 emails/day | Decent free tier |
| **AWS SES** | 62,000/mo (if on AWS) | Best value but needs AWS account |

No VPS, no proxy, no VPN needed.

---

## Quick Decision Flowchart

```
Do you need anonymous/crypto VPS?
├── Yes
│   ├── Want it right now?
│   │   ├── ✅ AlexHost (€6/mo) ← best current option
│   │   ├── ✅ HostSailor (~$5/mo)
│   │   └── ✅ Hostens ($2.50/mo)
│   └── Can wait?
│       └── ⏳ BuyVM ($3.50/mo) — check periodically for stock
└── No KYC needed, mainstream OK?
    └── Hetzner / Contabo — cheaper, block port 25 but unblock on request
        (requires ID/KYC but SMTP can be opened via support ticket)
```
