# Shadow Trace Ops KQL Template Parameters

Supported placeholders:

- `{TargetUser}` - resolved investigation UPN
- `{TargetAccount}` - account name before @
- `{TargetDomain}` - domain after @
- `{LookbackDays}` - selected report lookback

Example:

```kql
let TargetUser = "{TargetUser}";
DeviceLogonEvents
| where Timestamp > ago({LookbackDays}d)
| where AccountUpn =~ TargetUser
```

When the report renders the playbook side panel, Shadow Trace Ops replaces the placeholders with the current investigation context.
