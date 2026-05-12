<#
.SYNOPSIS
    Defender for Cloud Apps Investigation Toolkit - Phase 1

.DESCRIPTION
    PowerShell WinForms-based post-authentication investigation and defensive gap assessment toolkit.
    Phase 1 is read-only and advisory.

    Phase 1 priorities:
    - Keep the MDE Deployment Toolkit-style WinForms interface.
    - Keep buttons spaced out across rows as the interface grows.
    - Log every major action to the UI and to disk.
    - Connect to Microsoft Graph using read-only permissions.
    - Resolve the investigation target user.
    - Collect initial Entra ID identity risk data where permissions/licensing allow.
    - Collect initial sign-in log data where permissions allow.
    - Prepare structured placeholders for MDCA, XDR, OAuth, session behavior, and DLP collection.
    - Generate a human-readable HTML investigation report.
    - Remain advisory and avoid automated remediation.

.NOTES
    Project: Defender for Cloud Apps Investigation Toolkit
    Phase: 1
    Mode: Read-only / Advisory
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

$Script:RootPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Script:ConfigPath = Join-Path $Script:RootPath "Config"
$Script:LogPath = Join-Path $Script:RootPath "Logs"
$Script:ReportPath = Join-Path $Script:RootPath "Reports"
$Script:ExportPath = Join-Path $Script:RootPath "Exports"

foreach ($Path in @($Script:ConfigPath, $Script:LogPath, $Script:ReportPath, $Script:ExportPath)) {
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

$Script:LogFile = Join-Path $Script:LogPath ("MDCA-Investigation-Toolkit-Phase1-{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$Script:CurrentReportFile = $null
$Script:Investigation = $null

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------

function Write-ToolLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    if ($Script:txtLog -and -not $Script:txtLog.IsDisposed) {
        $Script:txtLog.AppendText("$entry`r`n")
        $Script:txtLog.SelectionStart = $Script:txtLog.Text.Length
        $Script:txtLog.ScrollToCaret()
    }

    Add-Content -Path $Script:LogFile -Value $entry
}

function New-SectionLabel {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 350
    )

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.Size = New-Object System.Drawing.Size($W, 24)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(49, 22, 64)
    return $lbl
}

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [scriptblock]$OnClick,
        [int]$W = 170,
        [int]$H = 34
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $btn.BackColor = [System.Drawing.Color]::White
    $btn.Add_Click($OnClick)
    return $btn
}

function ConvertTo-HtmlList {
    param([array]$Items)

    if (-not $Items -or $Items.Count -eq 0) {
        return "<li>No items were collected for this section in Phase 1.</li>"
    }

    return ($Items | ForEach-Object {
        "<li>$([System.Web.HttpUtility]::HtmlEncode([string]$_))</li>"
    }) -join "`n"
}

function Initialize-InvestigationObject {
    param([string]$UserPrincipalName)

    $Script:Investigation = [ordered]@{
        ToolkitPhase       = "Phase 1"
        Mode               = "Read-only / Advisory"
        UserPrincipalName  = $UserPrincipalName
        StartTime          = Get-Date
        EndTime            = $null
        IdentityRisk       = @()
        Authentication     = @()
        CloudActivity      = @()
        SessionBehavior    = @()
        OAuthActivity      = @()
        Alerts             = @()
        DlpVisibility      = @()
        ObservedRisks      = @()
        PotentialGaps      = @()
        Recommendations    = @()
        InvestigationPivots = @()
        Priority           = "Review Required"
    }
}

# ------------------------------------------------------------
# Connection / Collection Functions
# ------------------------------------------------------------

function Connect-InvestigationServices {
    Write-ToolLog "Connecting to Microsoft Graph..." "INFO"

    try {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        $Scopes = @(
            "User.Read.All",
            "Directory.Read.All",
            "AuditLog.Read.All",
            "Reports.Read.All",
            "IdentityRiskyUser.Read.All",
            "IdentityRiskEvent.Read.All",
            "SecurityEvents.Read.All"
        )

        Write-ToolLog "Requested Graph scopes: $($Scopes -join ', ')" "INFO"
        Connect-MgGraph -Scopes $Scopes -NoWelcome

        $Context = Get-MgContext
        if ($Context) {
            Write-ToolLog "Connected to Microsoft Graph tenant: $($Context.TenantId)" "SUCCESS"
        }
        else {
            Write-ToolLog "Microsoft Graph connection completed, but no context was returned." "WARN"
        }
    }
    catch {
        Write-ToolLog "Connection failed: $($_.Exception.Message)" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Connection failed. Review the log for details.",
            "Connection Error",
            "OK",
            "Error"
        ) | Out-Null
    }
}

function Get-GraphConnectionStatus {
    try {
        $context = Get-MgContext -ErrorAction Stop
        if ($context -and $context.Account) {
            return $true
        }
    }
    catch {
        return $false
    }
    return $false
}

function Resolve-InvestigationUser {
    param([string]$UserPrincipalName)

    Write-ToolLog "Resolving target user: $UserPrincipalName" "INFO"

    try {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        $user = Get-MgUser -UserId $UserPrincipalName -Property "id,displayName,userPrincipalName,mail,accountEnabled,createdDateTime,userType,department,jobTitle" -ErrorAction Stop

        $Script:Investigation.UserSummary = [ordered]@{
            Id                = $user.Id
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Mail              = $user.Mail
            AccountEnabled    = $user.AccountEnabled
            CreatedDateTime   = $user.CreatedDateTime
            UserType          = $user.UserType
            Department        = $user.Department
            JobTitle          = $user.JobTitle
        }

        Write-ToolLog "Resolved user: $($user.DisplayName) <$($user.UserPrincipalName)>" "SUCCESS"
        return $user
    }
    catch {
        Write-ToolLog "Could not resolve user $UserPrincipalName. $($_.Exception.Message)" "ERROR"
        $Script:Investigation.UserSummary = [ordered]@{
            UserPrincipalName = $UserPrincipalName
            ResolutionStatus  = "Failed"
            Error             = $_.Exception.Message
        }
        return $null
    }
}

function Get-IdentityRiskPhase1 {
    param(
        [string]$UserId,
        [string]$UserPrincipalName
    )

    Write-ToolLog "Collecting Entra ID risky user and risk detection information." "INFO"

    try {
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

        if ($UserId) {
            try {
                $riskyUser = Get-MgRiskyUser -RiskyUserId $UserId -ErrorAction Stop
                if ($riskyUser) {
                    $Script:Investigation.IdentityRisk += "Risky user record found. Risk level: $($riskyUser.RiskLevel). Risk state: $($riskyUser.RiskState). Risk detail: $($riskyUser.RiskDetail)."
                    Write-ToolLog "Risky user record found for $UserPrincipalName." "SUCCESS"
                }
            }
            catch {
                $Script:Investigation.IdentityRisk += "No risky user record was returned, or the tenant/license/permissions did not allow risky user retrieval."
                Write-ToolLog "Risky user lookup did not return a record or failed: $($_.Exception.Message)" "WARN"
            }
        }

        try {
            $filter = "userPrincipalName eq '$UserPrincipalName'"
            $detections = Get-MgRiskDetection -Filter $filter -Top 25 -ErrorAction Stop

            if ($detections) {
                foreach ($detection in $detections) {
                    $Script:Investigation.IdentityRisk += "Risk detection: $($detection.RiskType) | Level: $($detection.RiskLevel) | State: $($detection.RiskState) | Detected: $($detection.DetectedDateTime)"
                }
                Write-ToolLog "Collected $($detections.Count) identity risk detection record(s)." "SUCCESS"
            }
            else {
                $Script:Investigation.IdentityRisk += "No identity risk detections were returned for this user in the initial Phase 1 query."
                Write-ToolLog "No identity risk detections returned for $UserPrincipalName." "INFO"
            }
        }
        catch {
            $Script:Investigation.IdentityRisk += "Risk detection collection could not be completed. Review permissions, licensing, and Graph availability."
            Write-ToolLog "Risk detection collection failed: $($_.Exception.Message)" "WARN"
        }
    }
    catch {
        $Script:Investigation.IdentityRisk += "Microsoft.Graph.Identity.SignIns module was unavailable or could not be imported."
        Write-ToolLog "Identity risk module import failed: $($_.Exception.Message)" "ERROR"
    }
}

function Get-SignInActivityPhase1 {
    param([string]$UserPrincipalName)

    Write-ToolLog "Collecting recent sign-in activity for $UserPrincipalName." "INFO"

    try {
        Import-Module Microsoft.Graph.Reports -ErrorAction Stop

        $startTime = (Get-Date).AddDays(-7).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $filter = "userPrincipalName eq '$UserPrincipalName' and createdDateTime ge $startTime"

        $signIns = Get-MgAuditLogSignIn -Filter $filter -Top 25 -ErrorAction Stop

        if ($signIns) {
            foreach ($signIn in $signIns) {
                $status = if ($signIn.Status -and $signIn.Status.ErrorCode -eq 0) { "Success" } else { "Failure/Interrupted" }
                $caStatus = $signIn.ConditionalAccessStatus
                $app = $signIn.AppDisplayName
                $ip = $signIn.IpAddress
                $location = if ($signIn.Location) { "$($signIn.Location.City), $($signIn.Location.State), $($signIn.Location.CountryOrRegion)" } else { "Unknown" }
                $risk = "RiskLevelAggregated=$($signIn.RiskLevelAggregated); RiskState=$($signIn.RiskState); RiskDetail=$($signIn.RiskDetail)"

                $Script:Investigation.Authentication += "$($signIn.CreatedDateTime) | $status | App: $app | IP: $ip | Location: $location | CA: $caStatus | $risk"
            }

            Write-ToolLog "Collected $($signIns.Count) recent sign-in record(s)." "SUCCESS"
        }
        else {
            $Script:Investigation.Authentication += "No recent sign-in records were returned for this user in the initial 7-day Phase 1 query."
            Write-ToolLog "No recent sign-in records returned for $UserPrincipalName." "INFO"
        }
    }
    catch {
        $Script:Investigation.Authentication += "Sign-in collection could not be completed. Review AuditLog.Read.All, Reports.Read.All, tenant retention, and Graph module availability."
        Write-ToolLog "Sign-in collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Add-Phase1CloudAndGapPlaceholders {
    Write-ToolLog "Adding Phase 1 MDCA, session, OAuth, XDR, and DLP investigation placeholders." "INFO"

    if ($Script:chkCloud.Checked) {
        $Script:Investigation.CloudActivity += "Review downloads, uploads, file access, sharing, mass activity, and abnormal cloud usage in Defender for Cloud Apps."
        $Script:Investigation.CloudActivity += "Correlate cloud activity timestamps with successful authentication events and alert timestamps."
    }

    if ($Script:chkSession.Checked) {
        $Script:Investigation.SessionBehavior += "Review unmanaged device access and whether Conditional Access App Control session policies applied."
        $Script:Investigation.SessionBehavior += "Review risky session behavior, session control enforcement, and monitored versus blocked activity."
    }

    if ($Script:chkOAuth.Checked) {
        $Script:Investigation.OAuthActivity += "Review OAuth consent activity, newly consented applications, high-privilege delegated permissions, and unusual app access."
        $Script:Investigation.OAuthActivity += "Validate whether app governance controls exist for suspicious OAuth behavior."
    }

    if ($Script:chkAlerts.Checked) {
        $Script:Investigation.Alerts += "Review related Defender XDR incidents and alerts for the user, device, app, IP, and timeframe."
        $Script:Investigation.Alerts += "Correlate alert severity with identity risk, authentication context, cloud activity, and session behavior."
    }

    if ($Script:chkDlp.Checked) {
        $Script:Investigation.DlpVisibility += "Review DLP visibility for sensitive file movement, downloads, uploads, external sharing, and data exfiltration indicators."
        $Script:Investigation.DlpVisibility += "Validate whether large data movement has matching DLP, MDCA, or audit visibility."
    }
}

function Invoke-Phase1AssessmentLogic {
    Write-ToolLog "Running Phase 1 advisory assessment logic." "INFO"

    $Script:Investigation.ObservedRisks += "Successful authentication does not automatically mean the resulting session should be trusted."
    $Script:Investigation.ObservedRisks += "Post-authentication activity should be reviewed across identity, cloud apps, OAuth, sessions, XDR alerts, and DLP visibility."

    if ($Script:Investigation.IdentityRisk.Count -gt 0) {
        $Script:Investigation.ObservedRisks += "Identity risk data or identity risk review notes are present for this investigation."
    }

    if ($Script:Investigation.Authentication.Count -gt 0) {
        $Script:Investigation.ObservedRisks += "Authentication records or authentication review notes are present and should be correlated with cloud activity."
    }

    $Script:Investigation.PotentialGaps += "Review whether risky users are covered by session restrictions or additional monitoring."
    $Script:Investigation.PotentialGaps += "Review whether unmanaged device access is protected by Conditional Access App Control."
    $Script:Investigation.PotentialGaps += "Review whether suspicious OAuth activity is covered by app governance controls."
    $Script:Investigation.PotentialGaps += "Review whether large data movement has DLP visibility."
    $Script:Investigation.PotentialGaps += "Review whether risky sessions have documented response workflows."

    $Script:Investigation.Recommendations += "Validate Conditional Access and session control coverage for the selected user."
    $Script:Investigation.Recommendations += "Review OAuth consent, application permissions, and recent application activity."
    $Script:Investigation.Recommendations += "Correlate Defender XDR alerts with sign-in and cloud activity timelines."
    $Script:Investigation.Recommendations += "Review DLP policy visibility for sensitive cloud data movement."
    $Script:Investigation.Recommendations += "Document whether response actions are manual, automated, or undefined."

    $Script:Investigation.InvestigationPivots += "Review recent successful and risky sign-ins."
    $Script:Investigation.InvestigationPivots += "Pivot into Defender XDR incidents and alerts for this user."
    $Script:Investigation.InvestigationPivots += "Review Defender for Cloud Apps activity around the same timeframe."
    $Script:Investigation.InvestigationPivots += "Review OAuth consent events and application permission grants."
    $Script:Investigation.InvestigationPivots += "Validate Conditional Access, session controls, DLP, and response workflows."

    $riskWeight = 0
    if ($Script:Investigation.IdentityRisk.Count -gt 1) { $riskWeight += 1 }
    if ($Script:Investigation.Authentication.Count -gt 1) { $riskWeight += 1 }
    if ($Script:Investigation.OAuthActivity.Count -gt 0) { $riskWeight += 1 }
    if ($Script:Investigation.DlpVisibility.Count -gt 0) { $riskWeight += 1 }

    if ($riskWeight -ge 3) {
        $Script:Investigation.Priority = "Medium - Analyst Review Recommended"
    }
    else {
        $Script:Investigation.Priority = "Review Required"
    }
}

function Start-PostAuthInvestigation {
    $UserPrincipalName = $Script:txtUser.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Enter a user principal name before starting the investigation.",
            "Missing User",
            "OK",
            "Warning"
        ) | Out-Null
        return
    }

    Initialize-InvestigationObject -UserPrincipalName $UserPrincipalName

    Write-ToolLog "Starting Phase 1 post-authentication investigation for $UserPrincipalName" "INFO"
    Write-ToolLog "Workflow: identity risk -> authentication -> cloud activity -> session behavior -> findings -> potential gaps -> recommendations" "INFO"

    try {
        $isConnected = Get-GraphConnectionStatus
        if (-not $isConnected) {
            Write-ToolLog "Microsoft Graph does not appear connected. The tool will continue with advisory placeholders. Use Connect Services for live collection." "WARN"
        }

        $resolvedUser = $null
        if ($isConnected) {
            $resolvedUser = Resolve-InvestigationUser -UserPrincipalName $UserPrincipalName
        }
        else {
            $Script:Investigation.UserSummary = [ordered]@{
                UserPrincipalName = $UserPrincipalName
                ResolutionStatus  = "Not resolved - Graph not connected"
            }
        }

        if ($Script:chkIdentity.Checked -and $isConnected) {
            Get-IdentityRiskPhase1 -UserId $resolvedUser.Id -UserPrincipalName $UserPrincipalName
        }
        elseif ($Script:chkIdentity.Checked) {
            $Script:Investigation.IdentityRisk += "Graph is not connected. Identity risk data was not collected in this run."
        }

        if ($Script:chkAuthentication.Checked -and $isConnected) {
            Get-SignInActivityPhase1 -UserPrincipalName $UserPrincipalName
        }
        elseif ($Script:chkAuthentication.Checked) {
            $Script:Investigation.Authentication += "Graph is not connected. Sign-in activity was not collected in this run."
        }

        Add-Phase1CloudAndGapPlaceholders
        Invoke-Phase1AssessmentLogic

        $Script:Investigation.EndTime = Get-Date

        Write-ToolLog "Phase 1 investigation workflow completed for $UserPrincipalName." "SUCCESS"
        Write-ToolLog "Use Export HTML Report to generate the investigation report." "INFO"
    }
    catch {
        Write-ToolLog "Investigation failed: $($_.Exception.Message)" "ERROR"
    }
}

# ------------------------------------------------------------
# Report Functions
# ------------------------------------------------------------

function Export-InvestigationReport {
    if (-not $Script:Investigation) {
        [System.Windows.Forms.MessageBox]::Show(
            "No investigation data exists yet. Run an investigation first.",
            "No Investigation Data",
            "OK",
            "Warning"
        ) | Out-Null
        return
    }

    try {
        $upn = $Script:Investigation.UserPrincipalName
        $safeName = $upn.Replace("@", "_").Replace(".", "_").Replace("\", "_").Replace("/", "_")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportFile = Join-Path $Script:ReportPath "MDCA-Investigation-$safeName-$timestamp.html"

        Write-ToolLog "Exporting HTML investigation report for $upn" "INFO"

        $identityRiskItems = ConvertTo-HtmlList $Script:Investigation.IdentityRisk
        $authenticationItems = ConvertTo-HtmlList $Script:Investigation.Authentication
        $cloudActivityItems = ConvertTo-HtmlList $Script:Investigation.CloudActivity
        $sessionBehaviorItems = ConvertTo-HtmlList $Script:Investigation.SessionBehavior
        $oauthItems = ConvertTo-HtmlList $Script:Investigation.OAuthActivity
        $alertItems = ConvertTo-HtmlList $Script:Investigation.Alerts
        $dlpItems = ConvertTo-HtmlList $Script:Investigation.DlpVisibility
        $riskItems = ConvertTo-HtmlList $Script:Investigation.ObservedRisks
        $gapItems = ConvertTo-HtmlList $Script:Investigation.PotentialGaps
        $recommendationItems = ConvertTo-HtmlList $Script:Investigation.Recommendations
        $pivotItems = ConvertTo-HtmlList $Script:Investigation.InvestigationPivots

        $html = @"
<!DOCTYPE html>
<html>
<head>
<title>Defender for Cloud Apps Investigation Report</title>
<style>
body {
    font-family: Segoe UI, Arial, sans-serif;
    background-color: #f2f2f2;
    color: #222;
    margin: 24px;
}
h1 {
    color: #311640;
    margin-bottom: 4px;
}
h2 {
    color: #311640;
    margin-top: 0;
}
.meta {
    margin-bottom: 18px;
}
.section {
    background: #ffffff;
    border-left: 6px solid #311640;
    padding: 16px 18px;
    margin-bottom: 18px;
    box-shadow: 0 1px 4px rgba(0,0,0,.12);
}
.badge {
    display: inline-block;
    padding: 5px 9px;
    background: #eeeeee;
    border-radius: 4px;
    margin-right: 6px;
    font-size: 12px;
}
.priority {
    display: inline-block;
    padding: 8px 10px;
    background: #fff4ce;
    border: 1px solid #e0b000;
    border-radius: 4px;
    font-weight: bold;
}
li {
    margin-bottom: 7px;
}
.footer {
    color: #666;
    font-size: 12px;
    margin-top: 24px;
}
</style>
</head>
<body>

<h1>Defender for Cloud Apps Investigation Report</h1>
<div class="meta">
<p><strong>User:</strong> $upn</p>
<p><strong>Generated:</strong> $(Get-Date)</p>
<p><strong>Toolkit Phase:</strong> $($Script:Investigation.ToolkitPhase)</p>
<p><span class="badge">Read-only</span><span class="badge">Advisory</span><span class="badge">Post-authentication investigation</span></p>
</div>

<div class="section">
<h2>User Summary</h2>
<p>This Phase 1 report summarizes post-authentication activity review areas and potential defensive gaps for the selected user. Findings are advisory and should be validated by an analyst.</p>
</div>

<div class="section">
<h2>Investigation Priority</h2>
<p class="priority">$($Script:Investigation.Priority)</p>
</div>

<div class="section">
<h2>Identity Risk Summary</h2>
<ul>$identityRiskItems</ul>
</div>

<div class="section">
<h2>Authentication Context</h2>
<ul>$authenticationItems</ul>
</div>

<div class="section">
<h2>Cloud Activity Timeline</h2>
<ul>$cloudActivityItems</ul>
</div>

<div class="section">
<h2>Session Behavior</h2>
<ul>$sessionBehaviorItems</ul>
</div>

<div class="section">
<h2>OAuth and Application Activity</h2>
<ul>$oauthItems</ul>
</div>

<div class="section">
<h2>Alerts and Detections</h2>
<ul>$alertItems</ul>
</div>

<div class="section">
<h2>DLP and Data Movement Visibility</h2>
<ul>$dlpItems</ul>
</div>

<div class="section">
<h2>Observed Risk Indicators</h2>
<ul>$riskItems</ul>
</div>

<div class="section">
<h2>Potential Defensive Gaps</h2>
<ul>$gapItems</ul>
</div>

<div class="section">
<h2>Suggested Defensive Improvements</h2>
<ul>$recommendationItems</ul>
</div>

<div class="section">
<h2>Recommended Investigation Pivots</h2>
<ul>$pivotItems</ul>
</div>

<div class="footer">
<p>This report is read-only and advisory. It does not confirm compromise and does not perform remediation or enforcement actions.</p>
</div>

</body>
</html>
"@

        $html | Out-File -FilePath $reportFile -Encoding UTF8
        $Script:CurrentReportFile = $reportFile

        Write-ToolLog "HTML report exported: $reportFile" "SUCCESS"
        Start-Process $reportFile
    }
    catch {
        Write-ToolLog "Report export failed: $($_.Exception.Message)" "ERROR"
    }
}

function Open-CurrentReport {
    if ($Script:CurrentReportFile -and (Test-Path $Script:CurrentReportFile)) {
        Start-Process $Script:CurrentReportFile
        Write-ToolLog "Opened current report: $Script:CurrentReportFile" "INFO"
    }
    else {
        Write-ToolLog "No current report exists. Export a report first." "WARN"
        [System.Windows.Forms.MessageBox]::Show(
            "No current report exists. Export a report first.",
            "No Report",
            "OK",
            "Information"
        ) | Out-Null
    }
}

function Clear-InvestigationLog {
    $Script:txtLog.Clear()
    Write-ToolLog "On-screen log cleared. File logging continues at: $Script:LogFile" "INFO"
}

# ------------------------------------------------------------
# GUI
# ------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Defender for Cloud Apps Investigation Toolkit - Phase 1"
$form.Size = New-Object System.Drawing.Size(1120, 900)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(242, 242, 242)
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "Defender for Cloud Apps Investigation Toolkit"
$title.Location = New-Object System.Drawing.Point(20, 15)
$title.Size = New-Object System.Drawing.Size(850, 34)
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(49, 22, 64)
$form.Controls.Add($title)

$phase = New-Object System.Windows.Forms.Label
$phase.Text = "Phase 1 - Read-only post-authentication investigation and defensive gap assessment"
$phase.Location = New-Object System.Drawing.Point(22, 50)
$phase.Size = New-Object System.Drawing.Size(850, 22)
$phase.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($phase)

$form.Controls.Add((New-SectionLabel "Investigation Target" 20 85))

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "User Principal Name:"
$lblUser.Location = New-Object System.Drawing.Point(20, 120)
$lblUser.Size = New-Object System.Drawing.Size(160, 24)
$form.Controls.Add($lblUser)

$Script:txtUser = New-Object System.Windows.Forms.TextBox
$Script:txtUser.Location = New-Object System.Drawing.Point(180, 117)
$Script:txtUser.Size = New-Object System.Drawing.Size(360, 24)
$form.Controls.Add($Script:txtUser)

$form.Controls.Add((New-SectionLabel "Investigation Workflow" 20 165 420))

$workflow = New-Object System.Windows.Forms.Label
$workflow.Text = "Identity Risk -> Authentication -> Cloud Activity -> Session Behavior -> Findings -> Potential Gaps -> Recommendations"
$workflow.Location = New-Object System.Drawing.Point(20, 198)
$workflow.Size = New-Object System.Drawing.Size(1030, 30)
$workflow.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($workflow)

$form.Controls.Add((New-SectionLabel "Investigation Scope" 20 245 420))

$Script:chkIdentity = New-Object System.Windows.Forms.CheckBox
$Script:chkIdentity.Text = "Entra ID user risk and sign-in risk"
$Script:chkIdentity.Location = New-Object System.Drawing.Point(25, 280)
$Script:chkIdentity.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkIdentity.Checked = $true
$form.Controls.Add($Script:chkIdentity)

$Script:chkAuthentication = New-Object System.Windows.Forms.CheckBox
$Script:chkAuthentication.Text = "Authentication context and Conditional Access result"
$Script:chkAuthentication.Location = New-Object System.Drawing.Point(25, 310)
$Script:chkAuthentication.Size = New-Object System.Drawing.Size(380, 24)
$Script:chkAuthentication.Checked = $true
$form.Controls.Add($Script:chkAuthentication)

$Script:chkCloud = New-Object System.Windows.Forms.CheckBox
$Script:chkCloud.Text = "Defender for Cloud Apps activity"
$Script:chkCloud.Location = New-Object System.Drawing.Point(25, 340)
$Script:chkCloud.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkCloud.Checked = $true
$form.Controls.Add($Script:chkCloud)

$Script:chkSession = New-Object System.Windows.Forms.CheckBox
$Script:chkSession.Text = "Session behavior and unmanaged device access"
$Script:chkSession.Location = New-Object System.Drawing.Point(25, 370)
$Script:chkSession.Size = New-Object System.Drawing.Size(380, 24)
$Script:chkSession.Checked = $true
$form.Controls.Add($Script:chkSession)

$Script:chkOAuth = New-Object System.Windows.Forms.CheckBox
$Script:chkOAuth.Text = "OAuth and application activity"
$Script:chkOAuth.Location = New-Object System.Drawing.Point(450, 280)
$Script:chkOAuth.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkOAuth.Checked = $true
$form.Controls.Add($Script:chkOAuth)

$Script:chkAlerts = New-Object System.Windows.Forms.CheckBox
$Script:chkAlerts.Text = "Defender XDR alerts and detections"
$Script:chkAlerts.Location = New-Object System.Drawing.Point(450, 310)
$Script:chkAlerts.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkAlerts.Checked = $true
$form.Controls.Add($Script:chkAlerts)

$Script:chkDlp = New-Object System.Windows.Forms.CheckBox
$Script:chkDlp.Text = "DLP and data movement visibility"
$Script:chkDlp.Location = New-Object System.Drawing.Point(450, 340)
$Script:chkDlp.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkDlp.Checked = $true
$form.Controls.Add($Script:chkDlp)

$form.Controls.Add((New-SectionLabel "Actions" 20 430 420))

# Buttons are intentionally spaced across two rows to avoid crowding as the toolkit grows.
$btnConnect = New-Button "Connect Services" 20 465 { Connect-InvestigationServices }
$form.Controls.Add($btnConnect)

$btnInvestigate = New-Button "Run Investigation" 200 465 { Start-PostAuthInvestigation }
$form.Controls.Add($btnInvestigate)

$btnExportReport = New-Button "Export HTML Report" 380 465 { Export-InvestigationReport }
$form.Controls.Add($btnExportReport)

$btnOpenCurrentReport = New-Button "Open Current Report" 560 465 { Open-CurrentReport }
$form.Controls.Add($btnOpenCurrentReport)

$btnReports = New-Button "Open Reports" 740 465 { Start-Process $Script:ReportPath }
$form.Controls.Add($btnReports)

$btnLogs = New-Button "Open Logs" 920 465 { Start-Process $Script:LogPath }
$form.Controls.Add($btnLogs)

$btnConfig = New-Button "Open Config" 20 512 { Start-Process $Script:ConfigPath }
$form.Controls.Add($btnConfig)

$btnExports = New-Button "Open Exports" 200 512 { Start-Process $Script:ExportPath }
$form.Controls.Add($btnExports)

$btnClearLog = New-Button "Clear Log View" 380 512 { Clear-InvestigationLog }
$form.Controls.Add($btnClearLog)

$btnExit = New-Button "Exit" 560 512 { $form.Close() }
$form.Controls.Add($btnExit)

$Script:txtLog = New-Object System.Windows.Forms.TextBox
$Script:txtLog.Location = New-Object System.Drawing.Point(20, 575)
$Script:txtLog.Size = New-Object System.Drawing.Size(1070, 280)
$Script:txtLog.Multiline = $true
$Script:txtLog.ScrollBars = "Vertical"
$Script:txtLog.ReadOnly = $true
$Script:txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$Script:txtLog.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($Script:txtLog)

Write-ToolLog "Defender for Cloud Apps Investigation Toolkit loaded." "SUCCESS"
Write-ToolLog "Phase 1 mode: read-only and advisory." "INFO"
Write-ToolLog "Log file: $Script:LogFile" "INFO"
Write-ToolLog "Reports path: $Script:ReportPath" "INFO"

[void]$form.ShowDialog()
