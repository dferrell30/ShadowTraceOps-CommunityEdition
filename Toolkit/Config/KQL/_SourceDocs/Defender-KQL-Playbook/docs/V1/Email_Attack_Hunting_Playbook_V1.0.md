# Email Attack Hunting Playbook V1.0

Source: https://github.com/dferrell30/Defender-KQL-Playbook/tree/main/docs/V1

Purpose: practical KQL-based techniques to identify, investigate, and remediate email-based attacks.

Core focus:
- phishing campaigns
- malicious attachments and URLs
- URL click interaction
- campaign blast radius
- identity and endpoint pivots
- remediation workflow

Investigation questions:
1. Is this a campaign?
2. Was it delivered?
3. Did a user interact?
4. What is the blast radius?

Primary pivots:
- NetworkMessageId
- AccountUpn
- Url
- RecipientEmailAddress
- SenderFromAddress / SenderFromDomain

Remediation themes:
- block sender/domain/URL/hash
- purge delivered messages
- investigate clickers
- reset password/revoke sessions when validated
- review sign-in activity
