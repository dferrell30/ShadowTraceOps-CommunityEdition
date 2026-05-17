# Shadow Trace Ops Endpoint and Identity KQL Pack

These KQL files were created for the Shadow Trace Ops investigation workflow and are intended to be copied into the Defender-KQL-Playbook GitHub repository later.

## Endpoint queries

Location:

```text
Toolkit/Config/KQL/Endpoint
```

Files:

- 01-endpoint-user-logons-by-target-user.kql
- 02-endpoint-failed-logons-by-target-user.kql
- 03-endpoint-remote-interactive-logons.kql
- 04-endpoint-admin-or-elevated-logons.kql
- 05-endpoint-processes-after-user-logon.kql
- 06-endpoint-network-activity-from-user-devices.kql
- 07-endpoint-suspicious-script-execution-user-devices.kql

## Identity queries

Location:

```text
Toolkit/Config/KQL/Identity
```

Files:

- 01-entra-signin-summary-target-user.kql
- 02-entra-failed-signins-target-user.kql
- 03-entra-risky-signins-target-user.kql
- 04-entra-unmanaged-or-noncompliant-device-signins.kql
- 05-entra-legacy-client-or-basic-auth-patterns.kql
- 06-entra-rare-country-or-location-review.kql
- 07-identitylogonevents-target-user-pivot.kql

## Playbook JSON files

Location:

```text
Toolkit/Config/Playbooks
```

Files:

```text
endpoint-investigation-kql-pack.json
identity-investigation-kql-pack.json
```

## Notes

These queries use `column_ifexists()` where possible to reduce schema fragility across tenants. Some Advanced Hunting tables still require the correct product licensing, onboarding, RBAC, and telemetry presence.
