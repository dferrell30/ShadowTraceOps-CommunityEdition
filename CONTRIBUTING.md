# Contributing to Shadow Trace Ops

Thank you for your interest in contributing to **Shadow Trace Ops Community Edition**.

Shadow Trace Ops is a read-only Microsoft security investigation and defensive gap assessment framework focused on analyst workflow, Microsoft Graph collection, KQL pivots, investigation playbooks, source-health validation, and executive reporting.

This project is intended to help defenders investigate faster, document better, and identify visibility or control gaps across Microsoft security environments.

---

## Table of Contents

- [Project Goals](#project-goals)
- [Contribution Philosophy](#contribution-philosophy)
- [Ways to Contribute](#ways-to-contribute)
- [Before You Contribute](#before-you-contribute)
- [Development Guidelines](#development-guidelines)
- [PowerShell Guidelines](#powershell-guidelines)
- [KQL Contribution Guidelines](#kql-contribution-guidelines)
- [Playbook Contribution Guidelines](#playbook-contribution-guidelines)
- [Report/UI Contribution Guidelines](#reportui-contribution-guidelines)
- [Testing Expectations](#testing-expectations)
- [Submitting Issues](#submitting-issues)
- [Submitting Pull Requests](#submitting-pull-requests)
- [Security and Responsible Disclosure](#security-and-responsible-disclosure)
- [Scope Boundaries](#scope-boundaries)
- [License and Ownership](#license-and-ownership)

---

## Project Goals

Shadow Trace Ops is designed to:

- Accelerate Microsoft security investigations
- Guide analysts through repeatable investigation workflows
- Correlate identity, endpoint, cloud, email, OAuth, and XDR telemetry
- Provide KQL pivots that save investigation time
- Identify defensive gaps and telemetry limitations
- Produce analyst-ready and executive-ready reporting
- Remain read-only and advisory in the Community Edition

The project is not intended to replace Microsoft Defender XDR, Microsoft Sentinel, Entra ID, or analyst validation.

---

## Contribution Philosophy

Contributions should support the operational purpose of the tool.

Good contributions are:

- Practical
- Analyst-focused
- Read-only by default
- Clear and explainable
- Tested where possible
- Defensive in nature
- Useful during real investigations
- Respectful of telemetry limitations

Avoid changes that make the tool noisy, overly complex, destructive, or difficult for analysts to trust.

---

## Ways to Contribute

You can contribute by:

- Reporting bugs
- Testing the tool in lab environments
- Improving documentation
- Adding KQL pivots
- Improving investigation playbooks
- Suggesting workflow improvements
- Improving source-health validation
- Improving report clarity
- Adding screenshots or usage examples
- Validating telemetry behavior across tenants
- Suggesting new defensive gap checks

---

## Before You Contribute

Before opening a pull request, please:

1. Review the README.
2. Review the user guide.
3. Test your change locally.
4. Confirm the tool remains read-only.
5. Confirm existing report functionality still works.
6. Confirm investigation playbook pop-out blades still work.
7. Confirm the Executive Report remains separate from the Investigation Report.
8. Avoid introducing remediation or enforcement actions.

---

## Development Guidelines

### Preserve Current Baseline Behavior

The current V1 baseline behavior should be preserved unless a change is explicitly intended and documented.

Baseline expectations:

- Investigation Report remains analyst-focused.
- Investigation Report keeps pop-out playbook blades.
- KQL side panels remain functional.
- Executive Report remains separate.
- Executive Report does not include analyst pop-out blades.
- Community Edition remains read-only and advisory.
- Reports should be human-readable.
- Empty data areas should explain source-health or telemetry limitations.

### Do Not Break the Report Experience

Before submitting a change, verify:

- The PowerShell script launches.
- The UI loads.
- Reports export.
- The Investigation Report opens.
- The Executive Report opens.
- Playbook blades open.
- KQL copy/panel behavior still works.
- No parser errors are introduced.

---

## PowerShell Guidelines

Please follow these guidelines for PowerShell changes:

- Keep functions modular where possible.
- Use clear function names.
- Use `Write-ToolLog` for major actions.
- Use try/catch around Microsoft Graph and Advanced Hunting calls.
- Avoid hard crashes where a warning or source-health entry is better.
- Avoid destructive cmdlets.
- Avoid automatic remediation.
- Avoid tenant-specific assumptions.
- Avoid requiring administrator privileges unless absolutely necessary.
- Keep read-only Graph usage unless a future edition explicitly changes that model.

### Error Handling

When a collector fails, prefer:

```powershell
Write-ToolLog "Collector failed: $($_.Exception.Message)" "WARN"
Add-SourceHealthItem -CollectorName "CollectorName" -Status "Failed" -Detail $_.Exception.Message
```

Do not silently hide failures.

### Performance

Avoid long-running default queries.

When possible:

- Limit rows
- Respect lookback windows
- Avoid broad tenant-wide queries
- Use source-health validation
- Keep expensive collection opt-in

---

## KQL Contribution Guidelines

KQL is a major part of this project.

Good KQL contributions should:

- Be investigation-focused
- Use clear variable names
- Include a target UPN where applicable
- Use reasonable lookback windows
- Avoid excessive row returns
- Work in Microsoft Defender Advanced Hunting where possible
- Include comments when useful
- Avoid destructive or unsupported operations

### Recommended KQL Pattern

```kql
let TargetUser = "user@contoso.com";
let Lookback = 7d;
TableName
| where Timestamp > ago(Lookback)
| where AccountUpn =~ TargetUser
| project Timestamp, AccountUpn, ActionType, DeviceName, IPAddress
| order by Timestamp desc
```

### KQL Should Avoid

- Unbounded time ranges
- Tenant-wide hunting without filters
- Excessively large result sets
- Queries that assume every tenant has the same schema
- Queries that require private/internal tables

---

## Playbook Contribution Guidelines

Playbooks should help analysts answer:

- What happened?
- What should I check first?
- What pivots matter?
- What KQL should I run?
- What gaps might this indicate?
- What should be documented?
- What should be escalated?

A good playbook should include:

- Clear title
- Scenario
- Severity or priority guidance
- Analyst steps
- KQL references
- Expected evidence
- Possible defensive gaps
- Recommended validation steps

### Playbook Tone

Playbooks should be advisory.

Use wording such as:

- “Review whether…”
- “Validate whether…”
- “Consider checking…”
- “Potential gap…”
- “Recommended analyst pivot…”

Avoid unsupported conclusions such as:

- “This confirms compromise”
- “The user is compromised”
- “This is malicious”
- “Automatically remediate”

---

## Report/UI Contribution Guidelines

The report experience is a core part of Shadow Trace Ops.

### Investigation Report

The Investigation Report should remain analyst-focused.

It may include:

- Playbook pop-out blades
- KQL pivots
- analyst notes
- investigation workflow
- source health
- technical details
- telemetry explanations
- findings and recommended pivots

### Executive Report

The Executive Report should remain leadership-focused.

It should include:

- C-level metrics
- exposure visualizations
- priority guidance
- defensive gaps
- recommended timeline
- risk/difficulty/dependency views
- plain-English interpretation

It should not include analyst pop-out blades or highly technical clutter.

---

## Testing Expectations

Before submitting changes, test at minimum:

```powershell
.\Shadow-Trace-Ops.ps1
```

Then verify:

- UI launches
- Connect Services button works
- User investigation can run
- Investigation Report exports
- Executive Report exports
- Reports open in browser
- Playbook blades open
- KQL panels render
- Logs are written
- No parser errors occur

### Recommended Test Scenarios

If possible, test with:

- A user with no recent activity
- A user with recent sign-ins
- A user with failed sign-ins
- A user with Defender XDR alerts
- A tenant without Advanced Hunting data
- A tenant with limited permissions
- A lab tenant with EICAR or known test alerts

---

## Submitting Issues

When submitting an issue, include:

- Tool version or ZIP name
- PowerShell version
- Windows version
- Error message
- Screenshot if helpful
- Log excerpt from `Toolkit\Logs`
- Which report was affected
- Steps to reproduce
- Whether this occurred in Investigation Report or Executive Report

### Helpful Issue Format

```markdown
## Issue
Brief description.

## Environment
- Windows:
- PowerShell:
- Tool version:
- Tenant/licensing context if relevant:

## Steps to Reproduce
1.
2.
3.

## Expected Result

## Actual Result

## Logs / Screenshots
```

---

## Submitting Pull Requests

Pull requests should include:

- Clear description of the change
- Why the change is needed
- What was tested
- Screenshots for report/UI changes
- Any new permissions required
- Any new KQL tables used
- Any known limitations

### Pull Request Checklist

Before submitting:

- [ ] Script launches without parser errors
- [ ] Investigation Report exports
- [ ] Executive Report exports
- [ ] Playbook pop-out blades still work
- [ ] KQL side panels still work
- [ ] No destructive/remediation behavior added
- [ ] Source-health behavior is preserved
- [ ] Documentation updated if needed
- [ ] Screenshots added for UI/report changes

---

## Security and Responsible Disclosure

If you discover a security issue in the tool itself, please do not publicly disclose exploit details without giving maintainers a chance to review.

For security concerns, open a private communication channel if available or submit a minimal issue indicating that you would like to report a security concern.

Do not include sensitive tenant data, real user information, tokens, secrets, or production investigation evidence in public issues.

---

## Scope Boundaries

Community Edition V1 is read-only and advisory.

Out of scope for this edition:

- Automatic remediation
- Session revocation
- Account disablement
- OAuth grant removal
- Policy modification
- Device isolation
- Email purge
- Incident closure automation

These may be considered separately in future editions, but should not be introduced into Community Edition without explicit project direction.

---

## License and Ownership

Please review the repository license before contributing.

By contributing, you agree that your contribution may be included in the project under the repository’s license terms.

If you are contributing on behalf of an employer or organization, ensure you have permission to submit the contribution.

---

## Thank You

Shadow Trace Ops exists to help defenders investigate faster, document better, and identify gaps more clearly.

Thank you for helping improve the project.
