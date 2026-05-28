# Shadow Trace Ops — Community Edition V1

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=for-the-badge\&logo=powershell)
![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-Read%20Only-0078D4?style=for-the-badge\&logo=microsoft)
![Community Edition](https://img.shields.io/badge/Community-Edition-purple?style=for-the-badge)
![Status](https://img.shields.io/badge/Status-Operational%20Preview-success?style=for-the-badge)

> A PowerShell-based investigation and defensive gap assessment framework for Microsoft security environments.

---

# Overview

Shadow Trace Ops is a read-only investigation framework designed to help analysts correlate Microsoft security telemetry, accelerate investigations, standardize pivots, and identify potential defensive gaps.

The framework combines:

* Investigation reporting
* KQL playbooks
* Guided analyst pivots
* Pop-out investigation blades
* Telemetry correlation
* Executive exposure reporting
* Defensive gap discovery
* Source-health validation
* Microsoft Graph API collection

The goal is not just to answer:

> "What happened?"

But also:

> "What are we missing that allowed this to happen?"

---

# Core Focus Areas

Shadow Trace Ops focuses on investigation and telemetry correlation across:

* Microsoft XDR
* Entra ID
* Defender for Endpoint
* Defender for Office 365
* Defender for Cloud Apps
* OAuth and application activity
* Authentication and identity telemetry
* Endpoint and XDR context
* Email and URL investigation
* Advanced Hunting / KQL workflows
* Defensive gap visibility

---

# Key Features

## Investigation Report

The Investigation Report is designed for analysts and responders.

Features include:

* User-focused investigation workflow
* Identity and authentication analysis
* Endpoint and XDR context
* Cloud activity review
* OAuth and app activity analysis
* Email and URL investigation context
* Source health validation
* Potential defensive gap identification
* Investigation timelines
* Analyst workflow tracking
* Embedded KQL pivots
* Pop-out investigation playbooks

---

## Executive Report

The Executive Report is designed for:

* CISOs
* Directors
* Leadership
* Incident stakeholders
* Security management

The Executive Report focuses on:

* Exposure metrics
* Telemetry coverage
* Defensive gaps
* Recommended priorities
* Risk visibility
* Priority timelines
* Executive-level guidance
* Readiness and operational concerns

The Executive Report intentionally does **not** include analyst playbook pop-outs.

---

## Pop-Out Investigation Playbooks

The Investigation Report includes embedded investigation playbooks with:

* Guided pivots
* Investigation flow
* KQL references
* Analyst recommendations
* Triage direction
* Threat hunting guidance
* Operational context

The goal is to help analysts move through investigations faster and more consistently.

---

## KQL Side Panels

KQL templates are integrated directly into the investigation workflow.

Features include:

* User UPN auto-population
* Investigation-focused queries
* Identity pivots
* Endpoint pivots
* OAuth pivots
* Email and URL pivots
* Cloud investigation pivots
* Copy-to-clipboard functionality

---

## Source Health Validation

Source Health helps analysts understand:

* What data was successfully collected
* What failed
* What telemetry is unavailable
* What permissions may be missing
* What workloads may not be onboarded
* Whether investigation confidence is reduced

This helps prevent false assumptions based on empty sections or unavailable telemetry.

---

# Why This Exists

Many investigations require analysts to constantly pivot between:

* Entra ID
* Microsoft Defender XDR
* Advanced Hunting
* Cloud App Security
* Sign-in logs
* OAuth permissions
* Email telemetry
* Endpoint telemetry
* KQL queries
* Manual notes
* Executive summaries

Shadow Trace Ops was designed to help bring those pivots together into a guided investigation experience.

---

# Current Community Edition Goals

The Community Edition is focused on:

* Accelerating investigations
* Improving investigation consistency
* Standardizing pivots
* Improving analyst workflow
* Identifying defensive gaps
* Improving visibility into telemetry readiness
* Supporting Microsoft security investigations

---

# What This Tool Does NOT Do

Shadow Trace Ops does **not**:

* Automatically remediate users
* Disable accounts
* Revoke sessions
* Quarantine devices
* Change policies
* Replace Microsoft security tooling
* Replace analyst validation
* Confirm compromise by itself

The framework is read-only and advisory.

---

# Screenshots

> Add screenshots here.

Recommended screenshots:

* Investigation dashboard
* Playbook pop-out blade
* KQL side panel
* Executive report
* Timeline view
* Gap analysis section

---

# Architecture

```text
User Investigation
        ↓
Microsoft Graph API Collection
        ↓
Identity / Auth / XDR / Cloud Correlation
        ↓
Telemetry Validation & Source Health
        ↓
KQL Pivot & Playbook Guidance
        ↓
Investigation Report
        ↓
Executive Exposure Report
```

---

# Folder Structure

```text
Toolkit/
├── Shadow-Trace-Ops.ps1
├── Assets/
├── Config/
│   ├── KQL/
│   └── Playbooks/
├── Reports/
├── Logs/
└── Exports/
```

---

# Requirements

## Local Requirements

* Windows 10 or Windows 11
* PowerShell 5.1+
* Microsoft Graph PowerShell SDK
* Internet access
* Access to a Microsoft tenant

---

## Recommended Microsoft Graph Permissions

```text
User.Read.All
Directory.Read.All
AuditLog.Read.All
Reports.Read.All
IdentityRiskyUser.Read.All
IdentityRiskEvent.Read.All
SecurityEvents.Read.All
SecurityAlert.Read.All
SecurityIncident.Read.All
ThreatHunting.Read.All
```

Some permissions may require administrator consent.

---

# Installation

## Clone or Download

```powershell
git clone <repository-url>
```

Or download the ZIP and extract locally.

---

## Install Microsoft Graph PowerShell SDK

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

---

## Navigate to the Toolkit Folder

```powershell
cd "C:\Path\To\Toolkit"
```

---

## Unblock the Script

```powershell
Unblock-File .\Shadow-Trace-Ops.ps1
```

---

## Set Execution Policy for Current Session

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

---

## Launch the Tool

```powershell
.\Shadow-Trace-Ops.ps1
```

---

# Running an Investigation

## Step 1 — Connect Services

Click:

```text
Connect Services
```

Authenticate to Microsoft Graph.

---

## Step 2 — Enter User UPN

Example:

```text
user@contoso.com
```

---

## Step 3 — Choose Lookback Window

Recommended:

```text
7 days
```

Available:

* 7 days
* 30 days
* 90 days

---

## Step 4 — Run Investigation

Click:

```text
Run Investigation
```

The framework collects:

* Identity risk
* Authentication context
* OAuth activity
* XDR alerts/incidents
* Endpoint context
* Cloud activity
* Email and URL telemetry
* Potential gaps
* Source health

---

## Step 5 — Export Reports

Generate:

* Investigation Report
* Executive Report

Reports are saved to:

```text
Toolkit\Reports
```

---

# Investigation Workflow

Recommended analyst flow:

```text
Identity Risk
→ Authentication
→ Endpoint/XDR
→ OAuth Activity
→ Email/URL Investigation
→ Cloud Activity
→ Gap Analysis
→ KQL Pivots
→ Executive Reporting
```

---

# Operational Notes

## Important Guidance

A zero value in a section does not always mean:

```text
No activity occurred
```

It may indicate:

* No matching telemetry
* Missing permissions
* Table availability issues
* Retention limitations
* Source-health problems
* Licensing gaps
* Workload onboarding gaps

Always validate important findings in Microsoft security portals.

---

# Current Release Status

## Community Edition V1

Current baseline:

```text
Shadow-Trace-Ops-COMMUNITY-RELEASE-FINAL-EXECUTIVE-CLEVEL-v2.zip
```

Locked behaviors:

* Investigation Report with working pop-out playbook blades
* KQL side panels
* Analyst workflow layout
* Separate Executive Report
* Executive-focused exposure and gap reporting
* No analyst pop-outs in Executive Report

---

# Planned Future Enhancements

Potential future directions:

* Expanded hunting automation
* Additional telemetry normalization
* Microsoft Sentinel integration
* More dynamic executive scoring
* Investigation workflow customization
* Additional playbook coverage
* Threat-intelligence enrichment
* Timeline enhancements
* Investigation graphing improvements
* Case-management export

---

# Community Release Positioning

Shadow Trace Ops Community Edition should be considered:

```text
Operational Preview
```

This release is intended to:

* gather community feedback
* improve analyst workflow
* test investigation concepts
* improve telemetry correlation
* evolve investigation guidance

---

# Contributing

Feedback, ideas, validation testing, and operational suggestions are welcome.

Areas where feedback is especially valuable:

* Investigation workflow
* KQL pivots
* Telemetry quality
* Executive reporting
* Gap analysis
* Analyst usability
* Source health validation
* Microsoft workload coverage

---

# Disclaimer

Shadow Trace Ops is a read-only advisory investigation framework.

All findings should be validated by qualified analysts using the appropriate Microsoft security portals, logs, policies, and operational procedures.

The framework does not confirm compromise by itself.

The framework does not perform remediation.

Use in accordance with your organization's security, privacy, legal, and change-management requirements.

---

# Author

**Shadow Trace Ops — Community Edition V1**

Built from real-world investigation workflow challenges, telemetry correlation problems, and defensive gap analysis concepts within Microsoft security environments.

## Licensing

Shadow Suite Community Edition is licensed under the Business Source License 1.1 (BSL).

Permitted:
- personal use
- educational use
- internal organizational evaluation
- defensive security testing
- research and lab environments

Restricted without written authorization:
- commercial resale
- SaaS hosting
- MSSP/MSP redistribution
- managed service integration
- OEM redistribution
- rebranding
- derivative commercial offerings

See LICENSE.md and NOTICE.md for full details.


⚠️ Disclaimer
This tool is provided for educational, testing, and security validation purposes only.

Use of this tool should be limited to:

Authorized environments
Lab or approved enterprise systems
The author assumes no liability or responsibility for:

Misuse of this tool
Damage to systems
Unauthorized or improper use
By using this tool, you agree to use it in a lawful and responsible manner.
This project is not affiliated with or endorsed by Microsoft.


⚖️ Professional Disclaimer
This project is an independent work developed in a personal capacity.

The views, opinions, code, and content expressed in this repository are solely my own and do not reflect the views, policies, or positions of any current or future employer, client, or affiliated organization.

No employer, past, present, or future, has reviewed, approved, endorsed, or is in any way associated with these works.

This project was developed outside the scope of any employment and without the use of proprietary, confidential, or restricted resources.

All code/language in this repository is provided under the terms of the included MIT License.
