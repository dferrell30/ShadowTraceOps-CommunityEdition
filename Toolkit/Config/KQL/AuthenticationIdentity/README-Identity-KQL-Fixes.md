# Identity KQL Fix Notes

These queries avoid referencing newly-created columns inside the same `extend` statement.

Problem pattern:

```kql
| extend AccountUpnSafe = tostring(column_ifexists("AccountUpn", "")),
         Account = iff(isnotempty(AccountUpnSafe), AccountUpnSafe, "")
```

Some Advanced Hunting contexts may fail with:

```text
Failed to resolve scalar expression named 'AccountUpnSafe'
```

Fix pattern:

```kql
| extend AccountUpnSafe = tostring(column_ifexists("AccountUpn", ""))
| extend Account = iff(isnotempty(AccountUpnSafe), AccountUpnSafe, "")
```
