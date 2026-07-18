# Cold Email Infrastructure, Setup & Pricing — Deep Research Report

**Author:** Email Deliverability & Cold Outreach Specialist  
**Context:** Technical founder in Estonia (EU) with a port-blocked VPS and an approved SendPulse account  
**Primary Source:** [SMTPedia.com](https://smtpedia.com/)  
**Date:** July 19, 2026

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Infrastructure Choice: Self-Hosted vs Ready-Made Tools](#1-infrastructure-choice-self-hosted-vs-ready-made-tools)
3. [Exact Cold Outreach Setup (Step-by-Step)](#2-exact-cold-outreach-setup-step-by-step)
4. [Tool & Pricing Research for Campaigns](#3-tool--pricing-research-for-campaigns)
5. [Conclusion](#conclusion)

---

## Executive Summary

SMTPedia's 2026 guidance converges on one inescapable conclusion: **for cold email, a ready-made SaaS tool that leverages multiple real Google Workspace or Gmail mailboxes is vastly superior to any self-hosted SMTP setup.** The deliverability advantage of human-like inbox rotation, built-in warm-up, and the inherent trust of Google's infrastructure make the SaaS path the only sensible choice — especially for someone whose VPS cannot even open an SMTP port.

By adopting secondary domains, 2–5 Google Workspace mailboxes per domain, and a cold email platform like Smartlead or Instantly, you can achieve inbox placement that self-hosted SMTP (MailWizz, Postal, etc.) simply cannot match. The cost for sending 1,000–10,000 emails per month ranges from ~$50 to $250, including mailboxes and the SaaS fee, while a full stack that also collects and verifies leads adds roughly $80–$150 for each 5,000 contacts.

The recommended workflow separates true cold outreach (on the Google-based stack) from opt-in nurturing (on SendPulse), ensuring compliance and deliverability.

---

## 1. Infrastructure Choice: Self-Hosted vs Ready-Made Tools

### What SMTPedia Explicitly Recommends

SMTPedia's cornerstone article *"Cold Email Outreach in 2026 – Domain Strategy, Warmup, Tools, and Compliance"* is unambiguous: it **"strongly favors a ready-made SaaS approach with multiple inboxes over self-hosted SMTP."** The reasoning is rooted in the mechanics of modern mailbox provider algorithms, which overwhelmingly trust messages sent from real, human-like accounts on major platforms (Google, Microsoft) over server-IP-based SMTP, even when a reputable relay is used.

Crucially, SMTPedia's [Amazon SES Complete Guide 2026](https://smtpedia.com/) explicitly warns that Amazon SES (and by extension, most SMTP relays) forbids purchased or non-opt-in lists, ruling out cold email entirely. Even if a relay technically allowed it, the IP reputation of a generic relay or VPS server is instantly suspect, leading to spam folder placement or outright blocks.

Meanwhile, SMTPedia's [Best Self-Hosted Email Marketing Platforms in 2026](https://smtpedia.com/best-cold-email-tools/) lists MailWizz, Sendy, and Mumara with one-time licenses from $69–$89, and notes that these tools *"require hands-on management of SMTP, DNS, IP reputation, and deliverability."* That article, however, covers **opt-in** email marketing, not cold outreach.

### Comparison of Key Factors

#### Deliverability

| Factor | Self-Hosted | Ready-Made SaaS (Google Mailboxes) |
|--------|-------------|-------------------------------------|
| IP reputation | VPS IP has no history; months of careful building needed | Inherits Google's trusted infrastructure |
| Inbox placement | Often lands in spam or never arrives | Reliable inbox placement |
| Warm-up | Manual orchestration required | Automated warm-up via peer networks (Smartlead, Instantly) |

#### Compliance & Terms-of-Service Risk

| Factor | Self-Hosted | Ready-Made SaaS |
|--------|-------------|-----------------|
| Relay anti-spam policies | Almost always violated | Not applicable (uses Google's own SMTP) |
| GDPR transparency | Opaque server IP complicates "legitimate interest" | Real, identifiable Google mailboxes are transparent |
| Unsubscribe handling | Must implement manually | Built-in stop rules (replies, unsubscribes) |

#### Operational Complexity

| Aspect | Self-Hosted | Ready-Made SaaS |
|--------|-------------|-----------------|
| Setup time | Days to weeks | < 1 hour |
| Maintenance | MTA config, DNS, TLS, MTA-STS, DNSSEC, blacklist monitoring | None (platform handles it) |
| Skills required | DevOps / deliverability engineer | Basic DNS knowledge |

#### Cost at Small and Medium Volumes

| Approach | Upfront Cost | Monthly Cost | Deliverability Risk |
|----------|-------------|--------------|---------------------|
| Self-hosted (Contabo VPS + MailWizz) | ~$75 | ~$6 | **High** — emails likely land in spam |
| Ready-made SaaS (Instantly + 2 Google Workspace) | $0 | ~$49–$51 | **Low** — proven inbox placement |

### Clear Recommendation

**Adopt the ready-made cold email SaaS model with Google Workspace mailboxes.**

Given your VPS port block and the fact that SendPulse is reserved for opt-in mail, any attempt to build a self-hosted stack would waste time and deliverability. SMTPedia's evidence is overwhelming: the inbox-rotation approach is the only reliable, policy-safe path for B2B cold outreach in 2026.

---

## 2. Exact Cold Outreach Setup (Step-by-Step)

### a) Contact Collection (GDPR-Compliant "Legitimate Interest")

SMTPedia emphasizes that cold email is only permissible when targeting business contacts with a genuine "legitimate interest."

**Recommended Stack:**

| Tool | Use Case | Pricing |
|------|----------|---------|
| [Apollo.io](https://apollo.io) | Prospecting database with filtering by role, industry, company signals | Free (600 credits/mo), Paid from $49/mo |
| Alternative: Lusha / Cognism | Deeper EU-specific data | Varies |

**Process:**

1. **Define your Ideal Customer Profile (ICP)** — e.g., CTOs of SaaS companies in Europe
2. **Use Apollo's filters** to build a list of **business email addresses only** — never personal ones
3. **Export the list** and annotate the reason for legitimate interest per contact
4. **Never purchase a pre-packaged list** — SMTPedia and GDPR both view purchased lists as non-compliant

### b) Verification & List Hygiene

Verification is non-negotiable. SMTPedia states that a bounce rate above **3%** will tank your sender reputation.

**Recommended Tool:**

| Tool | Pricing | What It Catches |
|------|---------|-----------------|
| [SMTPing](https://smtpedia.com) (freemium) | ~$0.002–$0.005/email (bulk discounts) | Invalid, catch-all, disposable, spamtrap addresses |

**Workflow:**

1. Upload the prospect list to SMTPing
2. Remove addresses flagged as "invalid", "disposable", or "spamtrap"
3. For "catch-all" addresses, send at your own risk (avoid if bounce tolerance is low)
4. Re-verify any list that sits unused for **30 days** — data decays quickly

**Key Metrics to Monitor:**

| Metric | Target |
|--------|--------|
| Bounce rate | < 3% |
| Spam complaint rate | < 0.1% (Google's threshold) |
| Positive engagement (opens/replies) | As high as possible |

### c) Sending & Warm-Up Architecture

#### Domain and Mailbox Setup

SMTPedia introduces the concept of the **secondary domain** — a variation of your primary domain (e.g., `tryyourbrand.com`, `yourbrand.io`) used exclusively for cold outreach. This shields your main domain's reputation.

1. **Register 2–3 secondary domains** — do not send cold email from your main corporate domain
2. **Create 2–5 Google Workspace Business Starter accounts per domain** ($6/user/month)
3. **Configure DNS records:**
   - Google Workspace auto-configures **SPF**
   - Add a **DKIM TXT record**
   - Add a **DMARC policy** (`p=none` initially)
4. **Connect each mailbox** to your cold email SaaS via OAuth — this uses Google's native SMTP infrastructure, completely sidestepping your VPS port block

#### Warm-Up Process

SMTPedia defines warm-up as *"gradually increasing sending volume while generating positive engagement signals (opens, replies)"* to build each mailbox's individual reputation.

| Phase | Volume | Duration |
|-------|--------|----------|
| Start | 1–2 emails/day per mailbox | Day 1 |
| Gradual ramp | Increment daily | 2–4 weeks |
| Target | 30–50 emails/day per mailbox | After warm-up |

**Key Rules:**
- **Never skip warm-up** — sending 30 emails from a brand-new mailbox on day one guarantees spam folder placement
- Use automated warm-up pools (Smartlead/Instantly have built-in networks of real mailboxes)

#### Sequence Design

SMTPedia advises a multi-step sequence with intentional spacing:

| Step | Timing | Content |
|------|--------|---------|
| Email 1 | Day 1 | Value-driven opener, short, personalized with `{{first_name}}` and one custom line |
| Wait | 3–5 days | — |
| Email 2 | Follow-up | Reference the first message, add social proof |
| Wait | 5–7 days | — |
| Email 3 | Break-up | "Did I miss the mark?" type message with gentle CTA |

**Critical Rules:**
- Automatically stop the sequence **on a reply**, **out-of-office**, or **unsubscription**
- Daily volume per mailbox: **max 50 even after warm-up** (30–40 is safer)
- Scale by adding mailboxes, not by increasing per-mailbox volume

### d) Integrating SendPulse Without Mixing Cold and Opt-In

SendPulse is strictly for **opted-in contacts**; using it for cold email violates its anti-spam policies.

**Separation Flow:**

```
Cold Outreach (Google + SaaS stack)
    │
    └── Prospect replies with interest ──→ Zapier/Make automation
                                              │
                                              ▼
                                    SendPulse list "Warm Leads"
                                              │
                                              ▼
                                    Nurturing sequences
                                    (case studies, newsletters, invites)
                                    with visible unsubscribe link
                                              │
                                    If unsubscribe → remove from all lists
```

This keeps high-risk cold email and low-risk opt-in email completely separate, preserving deliverability and legal compliance.

---

## 3. Tool & Pricing Research for Campaigns

### Pricing Sources and Methodology

- **Cold email SaaS:** SMTPedia's [Top Picks directory](https://smtpedia.com/top-picks/) (Instantly: $37/mo, Smartlead: $39/mo)
- **Higher-tier plans:** Cross-checked against official tool websites
- **Google Workspace:** $6/user/month (public pricing)
- **Verification:** SMTPing's public tiers (~$10 for 5,000 verifications; ~$0.003/email)
- **Lead generation:** Apollo.io website pricing

### Assumptions

| Parameter | Value |
|-----------|-------|
| Safe sending limit | 40 emails/mailbox/day |
| Campaign duration | 1 month |
| Mailbox calculation | `(volume / 30 days) / 40 emails/day`, rounded up |
| Verification cost | $0.003/email |
| Apollo Pro plan | $79/mo for 5,000 credits |

### Scenario Definitions

| Scenario | Description |
|----------|-------------|
| **A: Have base, just send** | You already possess a clean, verified list; costs are only sending infrastructure (SaaS + mailboxes) |
| **B: No base (full stack)** | You must collect contacts (Apollo), verify them (SMTPing), and send (SaaS + mailboxes) |
| **C: Only collect base** | You only pay for data and verification; no sending infrastructure |

---

### Scenario A: Have Base, Just Send

| Volume | Mailboxes | Smartlead Plan | Instantly Plan | Workspace Cost | **Total (Smartlead)** | **Total (Instantly)** |
|--------|-----------|----------------|----------------|----------------|----------------------|----------------------|
| 1,000 | 2 | $39 (2k leads) | $37 (1k leads) | $12 | **$51** | **$49** |
| 5,000 | 5 | $94 (12k) | $97 (5k) | $30 | **$124** | **$127** |
| 10,000 | 9 | $94 | $197 (10k) | $54 | **$148** | **$251** |
| 50,000 | 42 | $169 (50k)* | $497 (50k) | $252 | **$421** | **$749** |

*\*Smartlead Ultimate plan at $169/month for up to 50,000 active leads.*

---

### Scenario B: No Base (Full Stack: Collect + Verify + Send)

| Volume | Apollo Plan | Verification ($0.003/e) | Sending (Smartlead) | **Total (Smartlead)** |
|--------|-------------|------------------------|---------------------|----------------------|
| 1,000 | Free* | $3 | $51 | **$54** |
| 5,000 | $79 (Pro, 5k credits) | $15 | $124 | **$218** |
| 10,000 | $149 (Custom/10k) | $30 | $148 | **$327** |
| 50,000 | $399 (est. enterprise) | $150 | $421 | **$970** |

*\*At 1,000 leads, Apollo's free tier provides 600 credits; remaining 400 covered via one-time purchase or another tool, estimated at $0 additional for simplicity.*

---

### Scenario C: Only Collect Base (Data + Verification, No Sending)

| Volume | Apollo Plan | Verification | **Total** |
|--------|-------------|--------------|-----------|
| 1,000 | $0 (free) | $3 | **$3** |
| 5,000 | $79 | $15 | **$94** |
| 10,000 | $149 | $30 | **$179** |
| 50,000 | $399 | $150 | **$549** |

---

### Key Takeaways from Pricing Prognosis

| Volume Range | Full Stack (Collect + Verify + Send) | Just Sending | Just Building List |
|-------------|--------------------------------------|--------------|-------------------|
| **1,000 emails** | ~$54 | ~$49–$51 | ~$3 |
| **5,000 emails** | ~$218 | ~$124–$127 | ~$94 |
| **10,000 emails** | ~$327 | ~$148–$251 | ~$179 |
| **50,000 emails** | ~$970 | ~$421–$749 | ~$549 |

**Important observations:**

- **Entry-level campaigns (1,000–5,000 emails)** are remarkably affordable — $50–$220/month covers everything from lead generation to sending
- **Scaling to 10,000 emails** adds more mailboxes, but total stays under $330/month for a full stack
- **At 50,000 emails, the mailbox cost becomes the largest line item.** This is where you might revisit deliverability vs. cost, but SMTPedia's consistent warning is clear: cutting mailbox costs by using a self-hosted relay will likely destroy deliverability
- **Lead generation costs scale linearly** with Apollo, but always factor in verification. The tiny $0.003/email to clean the list prevents bounce-related reputation damage

---

## Conclusion

SMTPedia's 2026 research unanimously points to the ready-made cold email stack as the only reliable foundation for B2B outreach. For a technical founder in Estonia — with a port-blocked VPS and an already-approved SendPulse account — the path is extraordinarily clear:

### Do NOT
- ❌ Waste time on self-hosted SMTP
- ❌ Attempt to use SendPulse for cold email
- ❌ Send from your main corporate domain
- ❌ Skip warm-up or verification

### DO
1. **Register 2–3 secondary domains** for cold outreach
2. **Create Google Workspace mailboxes** ($6/user/month)
3. **Subscribe to a cold email SaaS** (Smartlead or Instantly recommended)
4. **Collect contacts via Apollo.io** (GDPR-compliant legitimate interest)
5. **Verify your list via SMTPing** (target < 3% bounce rate)
6. **Warm up mailboxes gradually** over 2–4 weeks
7. **Design multi-step sequences** with automatic stop rules
8. **Use SendPulse only for opt-in nurturing** of engaged prospects

### Budget Snapshot

| What You Need | Monthly Cost Range |
|--------------|-------------------|
| Send 1,000 emails (already have list) | ~$49–$51 |
| Full stack: collect + verify + send 5,000 | ~$218 |
| Full stack: collect + verify + send 10,000 | ~$327 |
| Full stack: collect + verify + send 50,000 | ~$970 |

By anchoring your cold outreach in SMTPedia's thoroughly tested recommendations, you avoid the common pitfalls that kill deliverability and instead build a scalable, compliant engine that grows with your business.

---

*Research conducted July 2026. Pricing may vary; always verify current rates on tool websites.*