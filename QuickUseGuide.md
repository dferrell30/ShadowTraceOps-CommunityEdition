Shadow Throne v1.0 — GitHub Install Guide

1. Download the repository

From GitHub, click:

Code → Download ZIP

Or download the latest release ZIP from:

Releases → Shadow Throne v1.0
2. Extract the ZIP

Extract it to a local folder, for example:

C:\Tools\ShadowThrone

Recommended structure:

ShadowThrone
├── ShadowThrone.ps1
├── Assets
├── Web
├── Tools
├── Reports
├── Logs
├── Exports
├── Intelligence
└── Imports
3. Unblock the files

Right-click the downloaded ZIP before extracting:

Properties → Unblock → Apply

Or run this after extracting:

Get-ChildItem "C:\Tools\ShadowThrone" -Recurse | Unblock-File
4. Open PowerShell

Run PowerShell as your normal user.

Then go to the folder:

cd C:\Tools\ShadowThrone
5. Start Shadow Throne

Run:

Set-ExecutionPolicy -Scope Process Bypass
.\ShadowThrone.ps1

Shadow Throne will open in your browser.

Using Shadow Throne
Launch a tool

Click a Knight card:

Warrior → Shadow Deploy MDE
Gatekeeper → Shadow Deploy Defender for Office 365
Trial Master → Shadow Verify
Hunter → Shadow Trace Ops
Sentinel → Shadow CA placeholder

Each tool runs from its own packaged runtime folder under:

Tools\
Reports

Use the Reports page to view indexed reports and evidence from the tools.

Use:

Refresh Intel

after running a tool to update the report intelligence.

Tool folders

Use the folder buttons to open each tool’s runtime folder.

Known v1.0 Issue

The FRONT button is currently under construction.

Tools may launch behind the browser window. If a tool does not appear immediately, check the taskbar or move/minimize the browser.

This does not affect tool functionality.

Updating tools later

To update a Knight/tool later, replace its full runtime folder under:

Tools\<ToolName>

Example:

Tools\ShadowVerify

Restart Shadow Throne after replacing a tool folder.
