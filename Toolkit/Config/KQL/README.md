# Shadow Trace Ops KQL Folder

Put reusable `.kql` files here.

Recommended folders:
- Identity
- Authentication
- Endpoint
- EmailUrl
- CloudApps
- OAuth

In a playbook JSON, reference KQL files like this:

```json
"RelatedQueries": [
  "Authentication/signin-failures.kql",
  "CloudApps/cloud-downloads-and-sharing.kql"
]
```

The dashboard playbook side panel reads these files and renders the query text.
