# Shadow Trace Ops KQL and Playbook Taxonomy

This structure keeps analyst-facing playbooks clean and prevents overlap.

## Active Playbook Cards

1. Authentication & Identity Review
2. Email & URL Activity Review
3. Email Attack / Campaign Hunting
4. Endpoint / XDR Investigation
5. Cloud Apps & Session Activity
6. OAuth / App Consent Review
7. Cross-Layer Correlation

## KQL Categories

### AuthenticationIdentity
Sign-ins, identity risk, failed authentication, unmanaged/non-compliant device access, rare locations, legacy client review.

### EmailUrlActivity
User-level email interaction and URL click activity. Use this for delivered email + click correlation.

### EmailAttack
Campaign-scale email attack hunting. Use this for sender/domain spikes, reused subject campaigns, malicious attachment campaigns, spoofing, and spray-and-pray patterns.

### Endpoint
Device logons, process execution, remote access, scripting, and network activity from user devices.

### CloudApps
SaaS/cloud activity, downloads, uploads, sharing, session behavior, and data movement.

### OAuth
Consent grants, delegated permissions, high-interest scopes, and app governance.

### CrossLayer
Entity pivoting and correlation workflows across email, identity, endpoint, network, and alerts.

## Archive

Previous generated playbooks were moved to:

```text
Toolkit/Config/Playbooks/_Archive_PreConsolidation
```

They are preserved for reference but will not render as active dashboard cards.
