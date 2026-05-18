# Shadow Trace Ops Community Edition — Setup and Usage Guide

## Overview

Shadow Trace Ops Community Edition is an analyst-centric investigation and defensive gap assessment toolkit for Microsoft security operations.

It is designed to help analysts quickly review a user-centered investigation across:

- Entra ID identity and sign-in context
- Authentication behavior
- OAuth and application activity
- Defender XDR alert context
- Endpoint/XDR pivots
- Email and URL activity
- Cloud app and session behavior
- Defensive gaps
- Analyst notes, disposition, and potential remediation guidance

The tool is advisory and read-only. It is intended to assist investigation, documentation, and decision support. Analysts should validate findings before taking remediation action.

---

# 1. Prerequisites

## Required Workstation

Run Shadow Trace Ops from a Windows workstation with:

- Windows PowerShell 5.1 or PowerShell 7+
- Internet access to Microsoft Graph
- Permission to install/use Microsoft Graph PowerShell modules
- Browser available for interactive sign-in
- Access to the Microsoft tenant being investigated

## Required PowerShell Modules

At minimum, install Microsoft Graph PowerShell:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

If prompted, approve NuGet/provider installation.

You may also install commonly used Graph submodules:

```powershell
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
Install-Module Microsoft.Graph.Security -Scope CurrentUser
Install-Module Microsoft.Graph.Reports -Scope CurrentUser
```

---

# 2. Required Microsoft Permissions

Shadow Trace Ops uses read-only permissions.

Typical scopes include:

```text
User.Read.All
Directory.Read.All
AuditLog.Read.All
Reports.Read.All
Policy.Read.All
SecurityEvents.Read.All
SecurityAlert.Read.All
SecurityIncident.Read.All
ThreatHunting.Read.All
IdentityRiskyUser.Read.All
IdentityRiskEvent.Read.All
```

Some collectors may require additional tenant configuration, licensing, data availability, or Defender portal role access.

## Important

Advanced Hunting data may not be available unless:

- Defender XDR is available
- the required workload is licensed
- the relevant telemetry table exists
- the user has Defender XDR role access
- ThreatHunting.Read.All is consented

If a source is unavailable, Shadow Trace Ops should treat it as source health / telemetry readiness information, not proof that no suspicious activity occurred.

---

# 3. Folder Structure

Recommended repository structure:

```text
ShadowTraceOps-CommunityEdition
├─ Docs
├─ Examples
├─ Testing
├─ Toolkit
│  ├─ Assets
│  ├─ Config
│  │  ├─ KQL
│  │  ├─ Playbooks
│  │  ├─ GapDefinitions.json
│  │  ├─ InvestigationSettings.json
│  │  ├─ ReportSections.json
│  │  ├─ RiskIndicators.json
│  │  └─ ScoringModel.json
│  ├─ Exports
│  ├─ Logs
│  ├─ Modules
│  ├─ Reports
│  └─ Shadow-Trace-Ops.ps1
```

---

# 4. Initial Setup

## Step 1 — Download or clone the repository

```powershell
git clone https://github.com/<your-org-or-user>/ShadowTraceOps-CommunityEdition.git
```

Then change into the Toolkit folder:

```powershell
cd .\ShadowTraceOps-CommunityEdition\Toolkit
```

## Step 2 — Unblock downloaded files if needed

If the files were downloaded as a ZIP, run:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

## Step 3 — Allow the script for the current session

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## Step 4 — Run Shadow Trace Ops

```powershell
.\Shadow-Trace-Ops.ps1
```

Do not include a trailing slash.

Correct:

```powershell
.\Shadow-Trace-Ops.ps1
```

Incorrect:

```powershell
.\Shadow-Trace-Ops.ps1\
```

---

# 5. Connecting Services

In the Shadow Trace Ops UI:

1. Click **Connect Services**
2. Complete the Microsoft sign-in prompt
3. Consent to requested read-only permissions if prompted
4. Confirm the log pane shows a successful connection

## Note about WAM

On Windows, Web Account Manager may open an authentication window behind other windows.

If sign-in appears stuck:

- check behind open windows
- minimize PowerShell/ISE/terminal windows
- check the browser taskbar icon
- retry Connect Services if needed

---

# 6. Running a User Investigation

## Step 1 — Enter the target user

In **User Principal Name**, enter the UPN:

```text
user@domain.com
```

## Step 2 — Select lookback

Choose:

- 7 days
- 30 days
- 90 days

Recommended:

- 7 days for quick triage
- 30 days for normal investigation
- 90 days for deeper review or expanded investigation

## Step 3 — Select run mode

Use:

- **Standard** for normal investigations
- **Expanded** for deeper review

## Step 4 — Run Investigation

Click:

```text
Run Investigation
```

The tool should:

1. Resolve the user
2. Stop if the user cannot be resolved
3. Collect available telemetry
4. Evaluate source health
5. Build investigation context
6. Prepare report data

If the user does not resolve, the tool should stop and not generate a report.

---

# 7. Exporting Reports

After a successful investigation, click:

```text
Export HTML Report
```

The tool generates the primary dashboard report under:

```text
Toolkit\Reports
```

Then use:

```text
Open Current Report
```

or:

```text
Open Reports
```

---

# 8. Understanding the Primary Dashboard

The Primary Dashboard is the main analyst workspace.

It includes:

- Report Summary
- Investigation Score
- Where to Start
- Second Pivot
- Key Findings
- Analyst Workflow
- Investigation Disposition
- Playbooks
- Dynamic KQL
- Timeline Correlation
- Potential Remediation Steps
- Gap Closure Guidance
- Source Health
- KQL Template Validation

---

# 9. Investigation Score

The score is an advisory severity indicator.

It helps analysts decide how much attention the investigation may need.

Example classifications:

| Score | Classification | Meaning |
|---|---|---|
| 0-2 | Low | Routine review |
| 3-5 | Medium | Analyst review recommended |
| 6-8 | High | Prompt investigation |
| 9+ | Critical | Immediate review recommended |

## Important

A low score does not always mean no risk.

If telemetry is unavailable, confidence may be lower. Review Source Health and KQL validation.

---

# 10. Where to Start

The **Where to Start** section highlights the strongest area of concern.

Example starting areas:

- Authentication
- Identity Risk
- Email / URL
- Endpoint / XDR
- Cloud Activity
- OAuth / App Access
- Gaps & Exposures

Use this section to prioritize the first analyst pivot.

---

# 11. Playbooks

Playbooks are investigation runbooks.

They are stored under:

```text
Toolkit\Config\Playbooks
```

Each playbook can include:

- purpose
- severity
- triggers
- investigation steps
- related KQL
- expected results
- no-result meaning
- recommended actions

The report opens playbooks in a side panel.

Use playbooks to guide:

- junior analyst investigations
- repeatable SOC workflows
- SOP-style investigations
- escalation decisions

---

# 12. Dynamic KQL

KQL files are stored under:

```text
Toolkit\Config\KQL
```

KQL can include dynamic placeholders:

```text
{TargetUser}
{TargetAccount}
{TargetDomain}
{LookbackDays}
```

Example:

```kql
let TargetUser = "{TargetUser}";
DeviceLogonEvents
| where Timestamp > ago({LookbackDays}d)
| where AccountUpn =~ TargetUser
```

When rendered in the report, the placeholders are replaced with the current investigation context.

This allows the analyst to copy ready-to-run KQL directly from the report.

---

# 13. Analyst Notes and Disposition

The HTML report includes analyst-owned documentation areas.

Use these sections to document:

- analyst assessment
- validation outcome
- user confirmation
- escalation decisions
- false positive reasoning
- business justification
- remediation status

Disposition examples:

- Open
- Investigating
- Escalated to IR
- Monitoring Required
- Resolved - Benign
- Resolved - Confirmed Incident
- False Positive
- Inconclusive

---

# 14. Potential Remediation Steps

The report provides advisory remediation guidance based on investigation context.

Examples:

## Identity / Authentication

- Validate sign-in activity with the user
- Revoke sessions if suspicious authentication is confirmed
- Require password reset if credential compromise is suspected
- Review Conditional Access coverage

## Email / URL

- Identify users who clicked
- Review Safe Links verdict
- Purge delivered malicious messages if validated
- Block sender/domain/URL after confirmation

## OAuth / App Consent

- Review app publisher and permissions
- Remove risky grants if unauthorized
- Review consent governance

## Endpoint / XDR

- Review device timeline
- Validate suspicious process execution
- Collect triage package
- Isolate device only if compromise is confirmed

## Cloud Apps / Data Movement

- Validate downloads/uploads/sharing
- Review DLP visibility
- Review session controls
- Escalate to data owner if sensitive exposure is suspected

---

# 15. Gap Closure Guidance

Shadow Trace Ops does more than review alerts. It also identifies possible defensive gaps.

Examples:

- unmanaged device access
- missing session restrictions
- limited DLP visibility
- OAuth governance gaps
- telemetry availability issues
- source health limitations

Use Gap Closure Guidance to identify possible improvements to security controls.

---

# 16. Source Health

Source Health explains what telemetry was available or unavailable.

Review this carefully.

A missing table, unavailable workload, or permission limitation can reduce investigation confidence.

Do not treat missing telemetry as proof that nothing happened.

---

# 17. Common Investigation Scenarios

## Scenario 1 — Suspicious Sign-in

Use when:

- user has failed sign-ins
- MFA prompts occurred
- risky sign-in was reported
- sign-in came from unusual location
- unmanaged device was used

Workflow:

1. Run investigation for target user
2. Review Investigation Score
3. Open Authentication & Identity playbook
4. Review sign-ins and risky indicators
5. Pivot to cloud activity and endpoint context
6. Document analyst notes
7. Set disposition
8. Review remediation and gap closure guidance

---

## Scenario 2 — Phishing / URL Click

Use when:

- user clicked suspicious URL
- phishing email was delivered
- Safe Links event exists
- campaign investigation is needed

Workflow:

1. Run investigation for target user
2. Review Email & URL Activity
3. Open Email Attack / Campaign Hunting playbook
4. Review clicked URL and message details
5. Pivot to identity activity after click
6. Pivot to endpoint if execution is suspected
7. Review potential remediation steps
8. Document outcome

---

## Scenario 3 — OAuth Consent Review

Use when:

- app consent is suspicious
- high-risk permissions are granted
- unknown app appears
- user granted delegated permissions

Workflow:

1. Run investigation for target user
2. Review OAuth / App Consent section
3. Open OAuth playbook
4. Validate app publisher and scopes
5. Review activity after consent
6. Decide whether grant removal is recommended
7. Document disposition and remediation status

---

## Scenario 4 — Endpoint/XDR Review

Use when:

- endpoint alerts exist
- suspicious process activity is suspected
- remote logon occurred
- endpoint correlation is needed

Workflow:

1. Run investigation for target user
2. Review Endpoint / XDR indicators
3. Open Endpoint playbook
4. Run/copy endpoint KQL pivots
5. Validate device timeline in Defender XDR
6. Document endpoint findings
7. Escalate or monitor as appropriate

---

## Scenario 5 — Cloud App / Data Movement

Use when:

- suspicious downloads occurred
- file sharing is observed
- unmanaged session access occurred
- DLP visibility is a concern

Workflow:

1. Run investigation for target user
2. Review Cloud Apps & Session Activity
3. Review DLP and data movement guidance
4. Validate file activity
5. Review session controls
6. Document data owner or compliance escalation if needed

---

# 18. Recommended Analyst Flow

For most investigations:

```text
1. Run Investigation
2. Review score and where-to-start guidance
3. Check Source Health
4. Open the highest-priority playbook
5. Review dynamic KQL
6. Validate findings manually
7. Review timeline correlation
8. Review potential remediation steps
9. Review gap closure guidance
10. Add notes and disposition
11. Generate analyst summary
12. Save or export the report as needed
```

---

# 19. Troubleshooting

## Script does not start

Make sure you run:

```powershell
.\Shadow-Trace-Ops.ps1
```

not:

```powershell
.\Shadow-Trace-Ops.ps1\
```

## Execution policy blocks script

Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## User does not resolve

Check:

- UPN spelling
- Graph connection
- permissions
- tenant access

The tool should stop processing if the user cannot be resolved.

## Advanced Hunting query fails

Check:

- ThreatHunting.Read.All
- Defender XDR role access
- table availability
- licensing
- workload onboarding

## No endpoint telemetry

Check:

- Defender for Endpoint onboarding
- DeviceLogonEvents availability
- Advanced Hunting permissions
- source health results

## Report looks incomplete

Check:

- source health
- telemetry availability
- investigation mode
- lookback period
- Graph connection

---

# 20. Best Practices

- Treat the tool as advisory
- Validate before remediation
- Document analyst reasoning
- Review source health before conclusions
- Use playbooks for repeatability
- Use KQL pivots for validation
- Use disposition and notes for case handoff
- Use gap guidance for control improvement

---

# 21. Community Edition Notice

Shadow Trace Ops Community Edition is intended for:

- education
- internal security operations
- community collaboration
- Microsoft security investigation acceleration

It is not intended to replace analyst judgment, incident response procedures, or organizational approval workflows.

