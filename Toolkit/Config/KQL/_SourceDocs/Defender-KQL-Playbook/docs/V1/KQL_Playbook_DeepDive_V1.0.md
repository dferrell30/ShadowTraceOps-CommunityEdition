# KQL Playbook Deep Dive V1.0

Source: https://github.com/dferrell30/Defender-KQL-Playbook/tree/main/docs/V1

Investigation model:
Hunt -> Pivot -> Investigate -> Validate -> Decide

Entity pivoting strategy:
- User
- Device
- IP address
- URL / domain
- Email message ID

Cross-layer flow:
Email -> Identity -> Endpoint

Validation questions:
- Was the activity captured?
- Did expected signals appear?
- Were alerts triggered?
- Is anything missing?

Hunting should become detection when behavior is repeatable, reliable, and low noise.
