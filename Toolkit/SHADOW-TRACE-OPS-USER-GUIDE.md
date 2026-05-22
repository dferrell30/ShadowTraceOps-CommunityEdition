# Shadow Trace Ops — Community Edition User Guide

> **Release:** V1 Community Edition  
> **Mode:** Read-only / advisory investigation toolkit  
> **Primary script:** `Toolkit/Shadow-Trace-Ops.ps1`  
> **Reports:** Investigation Report and Executive Report

---

## Table of Contents

- [Overview](#overview)
- [What This Tool Does](#what-this-tool-does)
- [What This Tool Does Not Do](#what-this-tool-does-not-do)
- [Recommended Use Cases](#recommended-use-cases)
- [Prerequisites](#prerequisites)
- [Required Microsoft Graph Permissions](#required-microsoft-graph-permissions)
- [Folder Structure](#folder-structure)
- [Installation](#installation)
- [First Run Setup](#first-run-setup)
- [Launching the Tool](#launching-the-tool)
- [Connecting to Microsoft Graph](#connecting-to-microsoft-graph)
- [Running an Investigation](#running-an-investigation)
- [Choosing a Lookback Window](#choosing-a-lookback-window)
- [Using the Investigation Report](#using-the-investigation-report)
- [Using Playbook Pop-Out Blades](#using-playbook-pop-out-blades)
- [Using KQL Side Panels](#using-kql-side-panels)
- [Using the Executive Report](#using-the-executive-report)
- [Understanding the Metrics](#understanding-the-metrics)
- [Authentication and Identity Signals](#authentication-and-identity-signals)
- [Endpoint and XDR Signals](#endpoint-and-xdr-signals)
- [Source Health and Telemetry Readiness](#source-health-and-telemetry-readiness)
- [Exported Files](#exported-files)
- [Recommended Investigation Workflow](#recommended-investigation-workflow)
- [Common Troubleshooting](#common-troubleshooting)
- [Operational Notes](#operational-notes)
- [Release Status](#release-status)
- [Disclaimer](#disclaimer)

---

## Overview

**Shadow Trace Ops** is a PowerShell-based post-authentication investigation and defensive gap assessment toolkit for Microsoft security environments.

It is designed to help analysts quickly assess a user-focused security investigation by correlating:

- Entra ID identity risk
- Authentication and sign-in context
- OAuth and application activity
- Defender XDR alerts and incidents
- Endpoint context
- Email and URL click context
- Defender for Cloud Apps / cloud activity
- Source health and telemetry readiness
- Potential defensive gaps
- Recommended analyst pivots
- Executive-level exposure and priority guidance

The tool is read-only and advisory. It does not perform remediation actions.

---

## What This Tool Does

Shadow Trace Ops helps analysts answer questions such as:

- Was this user recently risky?
- Were there suspicious or failed authentication attempts?
- Are there Defender XDR alerts or incidents related to the user?
- Is there endpoint context available?
- Is email, URL click, OAuth, or cloud app activity visible?
- Are there telemetry gaps that reduce investigation confidence?
- What should the analyst review next?
- What should leadership understand about exposure, gaps, and priorities?

The tool generates two major report types:

| Report | Audience | Purpose |
|---|---|---|
| **Investigation Report** | SOC / security analyst | Deep technical workflow, playbooks, KQL pivots, findings, evidence, analyst notes |
| **Executive Report** | Leadership / C-level / management | Exposure summary, defensive gaps, timelines, priority guidance, risk-focused metrics |

---

## What This Tool Does Not Do

Shadow Trace Ops does **not**:

- Automatically remediate users
- Disable accounts
- Revoke sessions
- Modify Conditional Access policies
- Delete OAuth grants
- Quarantine devices
- Change Defender policies
- Replace analyst validation
- Replace Microsoft Defender XDR, Sentinel, or Entra ID portals

It is intended to speed up investigation, reporting, and decision support.

---

## Recommended Use Cases

Use Shadow Trace Ops for:

- Post-authentication investigation
- Suspicious user activity review
- User risk triage
- OAuth/app consent review
- Endpoint/XDR correlation
- Cloud session review
- Phishing follow-up investigation
- Defensive gap analysis
- Incident review documentation
- Analyst training
- SOP / runbook development
- Community lab validation
- Executive exposure reporting

---

## Prerequisites

### Local Requirements

Run the tool from a Windows machine with:

- Windows 10 or Windows 11
- PowerShell 5.1 or later
- Internet access
- Microsoft Graph PowerShell SDK
- Permission to run local PowerShell scripts
- Access to the target Microsoft tenant

### Recommended PowerShell Modules

Install Microsoft Graph PowerShell modules:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

If prompted, approve NuGet provider installation and module installation.

You may also need:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
Install-Module Microsoft.Graph.Reports -Scope CurrentUser
Install-Module Microsoft.Graph.Security -Scope CurrentUser
Install-Module Microsoft.Graph.Applications -Scope CurrentUser
```

---

## Required Microsoft Graph Permissions

The tool requests read-only Microsoft Graph permissions.

Recommended scopes:

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

### Permission Notes

Some permissions may require administrator consent.

Some data sources may return no data if:

- The tenant does not have the required license
- The signed-in user lacks Defender role access
- Advanced Hunting tables are unavailable
- Data retention does not include the selected time range
- The user had no matching activity
- The workload is not onboarded or generating telemetry

A zero count does not always mean there was no activity. Review source health and validate in Microsoft portals when needed.

---

## Folder Structure

Recommended repository layout:

```text
Defender-CloudApps-Session-Control-Playbook-main/
└── Toolkit/
    ├── Shadow-Trace-Ops.ps1
    ├── Assets/
    │   ├── ShadowTraceOpsLogo.png
    │   └── TenantLogo.png
    ├── Config/
    │   ├── KQL/
    │   └── Playbooks/
    ├── Exports/
    ├── Logs/
    └── Reports/
```

### Important Folders

| Folder | Purpose |
|---|---|
| `Toolkit` | Main script location |
| `Assets` | Optional logos used in UI and reports |
| `Config/KQL` | KQL query files used by playbooks and side panels |
| `Config/Playbooks` | JSON playbook definitions |
| `Reports` | Generated HTML reports |
| `Logs` | Runtime logs |
| `Exports` | JSON investigation snapshots and supporting exports |

---

## Installation

### Step 1 — Download or Clone the Repository

Clone or download the repository locally.

Example:

```powershell
git clone <your-repository-url>
```

Or download the ZIP from GitHub and extract it.

---

### Step 2 — Open PowerShell

Open PowerShell as your normal user.

You do not usually need to run as administrator unless your environment requires it for module installation or execution policy changes.

---

### Step 3 — Navigate to the Toolkit Folder

Example:

```powershell
cd "C:\Users\<YourUser>\OneDrive\Documents\Github\Defender-CloudApps-Session-Control-Playbook-main\Toolkit"
```

Confirm the script exists:

```powershell
Get-ChildItem
```

You should see:

```text
Shadow-Trace-Ops.ps1
```

---

### Step 4 — Unblock the Script

If the script was downloaded from the internet, unblock it:

```powershell
Unblock-File .\Shadow-Trace-Ops.ps1
```

You can also unblock all PowerShell files in the folder:

```powershell
Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File
```

---

### Step 5 — Set Execution Policy for This Session

If script execution is blocked, run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

This only changes execution policy for the current PowerShell session.

---

## First Run Setup

Before launching, confirm the following folders exist:

```text
Assets
Config
Logs
Reports
Exports
```

If they do not exist, the script attempts to create them.

### Optional Logo Setup

To show logos in the UI and reports:

1. Place the tool logo here:

```text
Toolkit\Assets\ShadowTraceOpsLogo.png
```

2. Optionally place a tenant/customer logo here:

```text
Toolkit\Assets\TenantLogo.png
```

If no logo is present, the tool still runs.

---

## Launching the Tool

From the `Toolkit` folder, run:

```powershell
.\Shadow-Trace-Ops.ps1
```

Do **not** add a trailing slash.

Correct:

```powershell
.\Shadow-Trace-Ops.ps1
```

Incorrect:

```powershell
.\Shadow-Trace-Ops.ps1\
```

If the UI opens, the tool launched successfully.

---

## Connecting to Microsoft Graph

### Step 1 — Click **Connect Services**

In the UI, click:

```text
Connect Services
```

The tool will request Microsoft Graph read-only permissions.

### Step 2 — Complete Browser Authentication

A browser or WAM authentication window should open.

Sign in with an account that has the required read permissions.

> **Note:** On Windows, Web Account Manager authentication may open behind other windows. Check the taskbar if the sign-in window is not visible.

### Step 3 — Confirm Connection

The log pane should show a successful connection message.

Example:

```text
Connected to Microsoft Graph tenant: <TenantId>
```

If the connection fails, review the log pane and ensure the required modules and permissions are available.

---

## Running an Investigation

### Step 1 — Enter the Target User

In the UPN field, enter the user principal name.

Example:

```text
user@contoso.com
```

### Step 2 — Choose a Lookback Window

Select one of the available lookback windows:

```text
7 days
30 days
90 days
```

### Step 3 — Confirm Investigation Scope

Use the checkboxes to include or exclude investigation areas.

Typical defaults include:

- Identity
- Authentication
- Cloud/session review
- OAuth/app activity
- XDR alerts/incidents
- Endpoint context
- Email/URL context
- DLP/data visibility review

### Step 4 — Run the Investigation

Click:

```text
Run Investigation
```

The tool will follow this workflow:

```text
Identity risk
→ Authentication
→ OAuth/app activity
→ Defender XDR alerts/incidents
→ Endpoint context
→ Email/URL context
→ Cloud/session review
→ Potential gaps
→ Recommendations
→ Timeline
→ Source health
```

### Step 5 — Monitor the Log Pane

The log pane shows what is running, what completed, what failed, and what was skipped.

A skipped collector is not always a failure. It may mean:

- Runtime KQL is disabled
- The selected mode does not run that collector
- The table is unavailable
- No matching records were found
- The tenant does not have the needed workload/license

---

## Choosing a Lookback Window

| Lookback | Recommended Use |
|---|---|
| **7 days** | Fast triage, recent incident review |
| **30 days** | Broader investigation and trend review |
| **90 days** | Historical summary and long-range review |

### Recommended Default

For most investigations, start with:

```text
7 days
```

Then expand to:

```text
30 days
```

Use 90 days only when you need historical context.

---

## Using the Investigation Report

After the investigation completes, export the analyst report.

Click:

```text
Export HTML Report
```

Depending on the current build, this may be labeled:

```text
Export Investigation Report
```

The Investigation Report is designed for analysts.

It includes:

- User summary
- Investigation metrics
- Identity risk
- Authentication context
- Cloud activity
- Session behavior
- OAuth/app activity
- Alerts and detections
- Endpoint context
- Email and URL click context
- DLP/data movement visibility
- Observed risk indicators
- Potential defensive gaps
- Suggested defensive improvements
- Recommended pivots
- Source health
- Playbooks
- KQL pop-out panels
- Analyst notes
- Workflow checkboxes

---

## Using Playbook Pop-Out Blades

The Investigation Report includes playbook cards.

Each playbook can open a side panel / pop-out blade.

### How to Use

1. Open the Investigation Report.
2. Scroll to the playbook section.
3. Click a playbook card.
4. A side panel opens.
5. Review:
   - scenario
   - triage steps
   - recommended pivots
   - KQL references
   - analyst guidance

### Why This Matters

The playbook blades are intended to act like built-in runbooks.

They help analysts answer:

- What should I check first?
- What does this signal mean?
- What KQL should I run?
- What defensive gap might this indicate?
- What should I document?

---

## Using KQL Side Panels

The playbook blades include KQL references.

KQL is stored under:

```text
Toolkit\Config\KQL
```

Playbook definitions are stored under:

```text
Toolkit\Config\Playbooks
```

### KQL Parameter Behavior

Where applicable, KQL templates are designed to use the investigated user UPN.

Common target parameter:

```kql
let TargetUser = "user@contoso.com";
```

### Analyst Use

Use the KQL side panels to:

- Copy queries
- Validate report findings
- Pivot in Advanced Hunting
- Investigate endpoint, identity, OAuth, email, and cloud context
- Build SOPs and repeatable investigation steps

---

## Using the Executive Report

The Executive Report is separate from the Investigation Report.

It is intended for:

- CISOs
- directors
- managers
- incident stakeholders
- leadership briefings
- risk and exposure summaries

The Executive Report should not include analyst pop-out blades.

It focuses on:

- C-level metrics
- exposure visualization
- defensive gaps
- priority guidance
- recommended change timeline
- risk, difficulty, and dependency views
- executive-ready interpretation

### How to Generate

After running an investigation, use the Executive report export option.

Depending on the build, this may be:

```text
Export Executive Report
```

or selected from the report mode dropdown.

### What to Look For

Review:

- total signals
- telemetry coverage
- potential gaps
- endpoint/XDR exposure
- identity risk
- cloud exposure
- OAuth/app exposure
- executive priority
- recommended timeline
- control improvement areas

---

## Understanding the Metrics

The Investigation Report and Executive Report include metrics that summarize collected signals.

Common metric areas:

| Metric | Meaning |
|---|---|
| **Auth Items** | Sign-in or authentication-related findings |
| **Risk Items** | Identity risk or risky user/sign-in context |
| **Cloud Items** | Cloud app activity, session, or MDCA-related context |
| **XDR Items** | Defender XDR alerts, incidents, or endpoint context |
| **URL Click Items** | Defender for Office 365 URL or email-related context |
| **Potential Gaps** | Defensive visibility, control, or process gaps |

### Important Metric Guidance

Metrics are not a final compromise verdict.

They are investigation indicators.

A high number means:

```text
Review this area.
```

It does not automatically mean:

```text
Confirmed compromise.
```

A zero count means:

```text
No matching data was collected by this tool in this run.
```

It does not always mean:

```text
No activity occurred.
```

Always review source health and validate important findings in Microsoft portals.

---

## Authentication and Identity Signals

Authentication telemetry can vary by tenant, permission, retention, and API behavior.

The tool may collect:

- successful sign-ins
- failed or interrupted sign-ins
- Conditional Access status
- client app
- IP address
- location
- device trust
- sign-in risk fields

Identity risk may include:

- risky user records
- risk detections
- risk level
- risk state
- detected risk type

### If Authentication Looks Empty

Check:

- Was the user active in the selected window?
- Does the account running the tool have `AuditLog.Read.All`?
- Are sign-in logs retained for the selected period?
- Can you see the sign-ins in Entra admin center?
- Did Graph return no rows?
- Does source health show an access or schema issue?

Validate manually in:

```text
Entra admin center → Monitoring → Sign-in logs
```

---

## Endpoint and XDR Signals

Endpoint and XDR context may include:

- Defender XDR alerts
- Defender incidents
- endpoint logon context
- Advanced Hunting results
- device names
- alert severity
- incident status
- detection source
- related user/device/app/IP evidence

### Endpoint Validation

Endpoint telemetry depends on:

- Microsoft Defender for Endpoint onboarding
- Defender XDR licensing
- Advanced Hunting table availability
- Defender portal role access
- `ThreatHunting.Read.All`
- table schema availability

### EICAR / Test Signals

If testing endpoint collection with EICAR, expect Defender to generate multiple raw telemetry events.

The report should be interpreted carefully:

- raw events may be noisy
- alerts/incidents are more meaningful
- validated findings matter more than raw row volume

---

## Source Health and Telemetry Readiness

Source Health helps explain what worked and what did not.

Review Source Health when:

- a section is empty
- a collector failed
- a table was unavailable
- permissions may be missing
- the report shows fewer signals than expected

Common statuses:

| Status | Meaning |
|---|---|
| **Completed** | Collector ran successfully |
| **Completed - No records matched** | Collector worked but found no matching data |
| **Skipped** | Collector intentionally did not run |
| **Failed** | Collector failed |
| **Telemetry unavailable** | Required source/table/permission was not available |
| **Advisory** | The tool provides guidance but did not collect live data |

---

## Exported Files

### Reports

Reports are saved to:

```text
Toolkit\Reports
```

Common report files:

```text
ShadowTraceOps-PrimaryDashboard-<user>-<timestamp>.html
ShadowTraceOps-DetailedWorkflow-<user>-<timestamp>.html
ShadowTraceOps-ExecutiveExposure-<user>-<timestamp>.html
ShadowTraceOps-ExecutiveSnapshot-<user>-<timestamp>.html
```

### JSON Exports

JSON exports are saved to:

```text
Toolkit\Exports
```

These can be used for:

- troubleshooting
- archiving
- future parsing
- evidence review
- report validation

### Logs

Logs are saved to:

```text
Toolkit\Logs
```

The log file format is usually:

```text
Shadow-Trace-Ops-yyyyMMdd.log
```

---

## Recommended Investigation Workflow

Use this workflow for a standard analyst investigation.

### Step 1 — Connect

Click:

```text
Connect Services
```

Confirm Graph connection succeeds.

---

### Step 2 — Enter User

Enter the target UPN.

Example:

```text
user@contoso.com
```

---

### Step 3 — Start with 7 Days

Choose:

```text
7 days
```

Run the investigation.

---

### Step 4 — Review Priority and Metrics

Open the Investigation Report.

Review:

- investigation priority
- metrics
- identity risk
- authentication
- XDR
- endpoint
- cloud/session
- gaps

---

### Step 5 — Open Playbook Blades

Open the relevant playbook pop-out blades.

Use them as guided runbooks.

---

### Step 6 — Copy KQL Pivots

Use the KQL side panels to validate:

- sign-in activity
- alerts
- incidents
- endpoint activity
- OAuth grants
- email/URL events
- cloud app activity

---

### Step 7 — Review Source Health

If any section is empty, check Source Health before assuming there is no activity.

---

### Step 8 — Add Analyst Notes

Use the report analyst notes and workflow checkboxes to document:

- what was reviewed
- what was validated
- what needs escalation
- what gaps were identified
- what actions are recommended

---

### Step 9 — Export Executive Report

Generate the Executive Report for leadership.

Use it to communicate:

- exposure
- priority
- visibility gaps
- recommended changes
- roadmap/timeline

---

### Step 10 — Save Evidence

Save:

- HTML reports
- JSON export
- relevant KQL results
- screenshots
- investigation notes

---

## Common Troubleshooting

### Script Does Not Run

If you see:

```text
The term '.\Shadow-Trace-Ops.ps1\' is not recognized
```

You likely added a trailing slash.

Use:

```powershell
.\Shadow-Trace-Ops.ps1
```

Not:

```powershell
.\Shadow-Trace-Ops.ps1\
```

---

### Execution Policy Blocks the Script

Run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run:

```powershell
.\Shadow-Trace-Ops.ps1
```

---

### Graph Login Window Does Not Appear

The sign-in window may be behind another window.

Check:

- taskbar
- browser windows
- Windows Account Manager prompt
- alt-tab list

---

### Report Looks Stale or Wrong

Close all old report browser tabs.

Then:

1. Open `Toolkit\Reports`
2. Sort by modified date
3. Open the newest HTML file manually

If needed, move old reports to a backup folder:

```powershell
Rename-Item .\Reports .\Reports_BACKUP
New-Item -ItemType Directory .\Reports
```

Then rerun and export a fresh report.

---

### Authentication Shows Zero

Check:

- Entra sign-in logs manually
- Graph permissions
- selected lookback window
- source health
- user activity
- tenant retention

Zero authentication rows does not always mean no authentication occurred.

---

### XDR or Endpoint Shows Zero

Check:

- Defender XDR roles
- Defender for Endpoint onboarding
- `ThreatHunting.Read.All`
- Advanced Hunting table availability
- source health
- whether runtime hunting is enabled
- whether there were actual matching alerts/incidents

---

### Advanced Hunting Errors

Advanced Hunting may fail due to:

- missing scope
- missing Defender role
- unavailable table
- schema variance
- licensing
- throttling
- no data

Use Source Health to classify the issue.

---

### Playbook Pop-Out Blades Do Not Open

Check that these folders exist:

```text
Toolkit\Config\Playbooks
Toolkit\Config\KQL
```

Also ensure the report was opened in a modern browser such as Edge or Chrome.

---

### KQL Looks Empty

Check:

- playbook JSON references
- KQL file paths
- `Toolkit\Config\KQL`
- whether the playbook has related queries

---

## Operational Notes

### Recommended Community Release Framing

This release is best described as:

```text
Operational Community Preview
```

or:

```text
Community Edition V1
```

Recommended language:

```text
Shadow Trace Ops Community Edition is a read-only investigation and defensive gap assessment toolkit intended to accelerate Microsoft security investigations, analyst workflows, KQL pivots, and executive reporting.
```

### Recommended Analyst Guidance

Use the tool as:

- an investigation accelerator
- a workflow guide
- a reporting assistant
- a gap assessment framework
- a training/runbook aid

Do not use it as the only source of truth.

---

## Release Status

Current V1 baseline:

```text
Shadow-Trace-Ops-COMMUNITY-RELEASE-FINAL-EXECUTIVE-CLEVEL-v2.zip
```

Locked V1 behavior:

- Investigation Report with working pop-out playbook blades
- KQL side panels
- analyst workflow layout
- separate Executive Report
- Executive Report focused on C-level exposure, gaps, timelines, priorities, and executive guidance
- no analyst pop-outs in Executive Report

---

## Disclaimer

Shadow Trace Ops is provided as a read-only advisory investigation toolkit.

All findings should be validated by qualified analysts using the appropriate Microsoft security portals, logs, policies, and organizational procedures.

The tool does not confirm compromise by itself.

The tool does not perform remediation.

Use in accordance with your organization's security, privacy, legal, and change management requirements.

---

## Quick Start

```powershell
cd "C:\Path\To\Repository\Toolkit"
Unblock-File .\Shadow-Trace-Ops.ps1
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Shadow-Trace-Ops.ps1
```

Then:

1. Click **Connect Services**
2. Authenticate to Microsoft Graph
3. Enter target UPN
4. Select lookback period
5. Click **Run Investigation**
6. Export the **Investigation Report**
7. Use playbook pop-out blades and KQL side panels
8. Export the **Executive Report**
9. Review gaps, priorities, and timeline
10. Save reports, notes, and JSON exports
