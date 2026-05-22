$Script:EnableRuntimeAdvancedHunting = $false # Phase 1 default: playbook KQL is advisory; runtime hunting is opt-in.
<#
.SYNOPSIS
    Shadow Trace Ops - Phase 1

.DESCRIPTION
    PowerShell WinForms-based post-authentication investigation and defensive gap assessment toolkit.
    Phase 1 is read-only and advisory.

    Phase 1 priorities:
    - Keep the MDE Deployment Toolkit-style WinForms interface.
    - Use a dark mode interface for analyst-friendly investigation workflows.
    - Keep buttons spaced out across rows as the interface grows.
    - Log every major action to the UI and to disk.
    - Connect to Microsoft Graph using read-only permissions.
    - Resolve the investigation target user.
    - Collect initial Entra ID identity risk data where permissions/licensing allow.
    - Collect initial sign-in log data where permissions allow.
    - Allow authentication log drill-down for 7, 30, or 90 days.
    - Prepare structured placeholders for MDCA, XDR, OAuth, session behavior, and DLP collection.
    - Generate a human-readable HTML investigation report.
    - Remain advisory and avoid automated remediation.

.NOTES
    Project: Shadow Trace Ops
    Phase: 1
    Mode: Read-only / Advisory
    Phase 1 Focus: XDR correlation, endpoint context, email/phishing context, and unified timeline
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

$Script:RootPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Script:ConfigPath = Join-Path $Script:RootPath "Config"
$Script:PlaybookPath = Join-Path $Script:ConfigPath "Playbooks"
$Script:KqlPath = Join-Path $Script:ConfigPath "KQL"
$Script:LogPath = Join-Path $Script:RootPath "Logs"
$Script:ReportPath = Join-Path $Script:RootPath "Reports"
$Script:ExportPath = Join-Path $Script:RootPath "Exports"
$Script:AssetPath = Join-Path $Script:RootPath "Assets"
$Script:LogoPath = Join-Path $Script:AssetPath "ShadowTraceOpsLogo.png"

foreach ($Path in @($Script:ConfigPath, $Script:LogPath, $Script:ReportPath, $Script:ExportPath, $Script:AssetPath)) {
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

$Script:LogFile = Join-Path $Script:LogPath ("Shadow-Trace-Ops-{0}.log" -f (Get-Date -Format "yyyyMMdd"))
$Script:CurrentReportFile = $null
$Script:TargetUserResolved = $false
$Script:LastResolvedUserPrincipalName = $null
$Script:AnalystNotes = ""
$Script:AnalystAssessment = ""
$Script:AnalystStatus = [ordered]@{}
$Script:CurrentSnapshotReport = $null
    $Script:Investigation = $null
# ------------------------------------------------------------
# Dark Mode Theme
# ------------------------------------------------------------

$Script:Theme = [ordered]@{
    FormBack      = [System.Drawing.Color]::FromArgb(18, 18, 24)
    PanelBack     = [System.Drawing.Color]::FromArgb(28, 28, 36)
    ControlBack   = [System.Drawing.Color]::FromArgb(36, 36, 46)
    ButtonBack    = [System.Drawing.Color]::FromArgb(49, 22, 64)
    ButtonHover   = [System.Drawing.Color]::FromArgb(68, 34, 88)
    ButtonFore    = [System.Drawing.Color]::FromArgb(245, 245, 245)
    TextFore      = [System.Drawing.Color]::FromArgb(235, 235, 240)
    MutedFore     = [System.Drawing.Color]::FromArgb(180, 180, 190)
    Accent        = [System.Drawing.Color]::FromArgb(183, 132, 255)
    AccentStrong  = [System.Drawing.Color]::FromArgb(202, 162, 255)
    Border        = [System.Drawing.Color]::FromArgb(80, 62, 98)
    LogBack       = [System.Drawing.Color]::FromArgb(10, 10, 14)
    LogFore       = [System.Drawing.Color]::FromArgb(210, 245, 220)
    InputBack     = [System.Drawing.Color]::FromArgb(24, 24, 31)
}

function Set-DarkControlStyle {
    param([System.Windows.Forms.Control]$Control)

    if (-not $Control) { return }

    $Control.BackColor = $Script:Theme.FormBack
    $Control.ForeColor = $Script:Theme.TextFore

    foreach ($child in $Control.Controls) {
        if ($child -is [System.Windows.Forms.Button]) {
            $child.BackColor = $Script:Theme.ButtonBack
            $child.ForeColor = $Script:Theme.ButtonFore
            $child.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $child.FlatAppearance.BorderColor = $Script:Theme.Border
            $child.FlatAppearance.BorderSize = 1
            $child.UseVisualStyleBackColor = $false
        }
        elseif ($child -is [System.Windows.Forms.TextBox]) {
            $child.BackColor = $Script:Theme.InputBack
            $child.ForeColor = if ($child.Multiline) { $Script:Theme.LogFore } else { $Script:Theme.TextFore }
            $child.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        }
        elseif ($child -is [System.Windows.Forms.ComboBox]) {
            $child.BackColor = $Script:Theme.InputBack
            $child.ForeColor = $Script:Theme.TextFore
            $child.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        }
        elseif ($child -is [System.Windows.Forms.CheckBox]) {
            $child.BackColor = $Script:Theme.FormBack
            $child.ForeColor = $Script:Theme.TextFore
            $child.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        }
        elseif ($child -is [System.Windows.Forms.Label]) {
            $child.BackColor = $Script:Theme.FormBack
            if ($child.Font.Bold) {
                $child.ForeColor = $Script:Theme.AccentStrong
            }
            else {
                $child.ForeColor = $Script:Theme.TextFore
            }
        }

        if ($child.Controls.Count -gt 0) {
            Set-DarkControlStyle -Control $child
        }
    }
}

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------

function Write-ToolLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    if ($Script:txtLog -and -not $Script:txtLog.IsDisposed) {
        $Script:txtLog.AppendText("$entry`r`n")
        $Script:txtLog.SelectionStart = $Script:txtLog.Text.Length
        $Script:txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
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
    $lbl.ForeColor = $Script:Theme.AccentStrong
    $lbl.BackColor = $Script:Theme.FormBack
    return $lbl
}

function Get-ImageDataUri {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $extension = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLower()
        $mime = switch ($extension) {
            "jpg"  { "image/jpeg" }
            "jpeg" { "image/jpeg" }
            "svg"  { "image/svg+xml" }
            default { "image/png" }
        }

        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $base64 = [System.Convert]::ToBase64String($bytes)
        return "data:$mime;base64,$base64"
    }
    catch {
        Write-ToolLog "Image could not be converted to data URI: $Path. $($_.Exception.Message)" "WARN"
        return $null
    }
}


function ConvertTo-SafeHtml {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return ""
    }

    $value = [string]$InputObject

    $value = $value.Replace("&","&amp;")
    $value = $value.Replace("<","&lt;")
    $value = $value.Replace(">","&gt;")
    $value = $value.Replace('"',"&quot;")
    $value = $value.Replace("'","&#39;")

    return $value
}


function Get-LogoHtml {
    $toolLogoUri = Get-ImageDataUri -Path $Script:LogoPath
    if ($toolLogoUri) {
        return "<img class='tool-logo' src='$toolLogoUri' alt='Shadow Trace Ops Logo' />"
    }

    return ""
}

function Get-TenantLogoHtml {
    $tenantLogoPath = Join-Path $Script:AssetPath "TenantLogo.png"
    $tenantLogoUri = Get-ImageDataUri -Path $tenantLogoPath

    if ($tenantLogoUri) {
        return "<img class='tenant-logo' src='$tenantLogoUri' alt='Tenant Logo' />"
    }

    return "<div class='tenant-logo-placeholder'>Tenant<br/>Logo</div>"
}

function Get-ReportMetricCardsHtml {
    $authCount = if ($Script:Investigation.Authentication) { $Script:Investigation.Authentication.Count } else { 0 }
    $riskCount = if ($Script:Investigation.IdentityRisk) { $Script:Investigation.IdentityRisk.Count } else { 0 }
    $cloudCount = 0
    if ($Script:Investigation.CloudActivity) { $cloudCount += $Script:Investigation.CloudActivity.Count }
    if ($Script:Investigation.CloudAppEvents) { $cloudCount += $Script:Investigation.CloudAppEvents.Count }
    $xdrCount = 0
    if ($Script:Investigation.Alerts) { $xdrCount += $Script:Investigation.Alerts.Count }
    if ($Script:Investigation.Incidents) { $xdrCount += $Script:Investigation.Incidents.Count }
    $urlCount = if ($Script:Investigation.UrlClickContext) { $Script:Investigation.UrlClickContext.Count } else { 0 }
    $gapCount = if ($Script:Investigation.PotentialGaps) { $Script:Investigation.PotentialGaps.Count } else { 0 }

    return @"
<div class='metric-grid'>
  <div class='metric-card'><div class='metric-icon'>AUTH</div><div class='metric-value'>$authCount</div><div class='metric-label'>Auth Items</div></div>
  <div class='metric-card'><div class='metric-icon'>RISK</div><div class='metric-value'>$riskCount</div><div class='metric-label'>Risk Items</div></div>
  <div class='metric-card'><div class='metric-icon'>CLOUD</div><div class='metric-value'>$cloudCount</div><div class='metric-label'>Cloud Items</div></div>
  <div class='metric-card'><div class='metric-icon'>XDR</div><div class='metric-value'>$xdrCount</div><div class='metric-label'>XDR Items</div></div>
  <div class='metric-card'><div class='metric-icon'>URL</div><div class='metric-value'>$urlCount</div><div class='metric-label'>URL Click Items</div></div>
  <div class='metric-card'><div class='metric-icon'>!</div><div class='metric-value'>$gapCount</div><div class='metric-label'>Potential Gaps</div></div>
</div>
"@
}

function Add-LogoToForm {
    param([System.Windows.Forms.Form]$Form)

    if (-not (Test-Path $Script:LogoPath)) {
        Write-ToolLog "Logo not found at $Script:LogoPath. Place ShadowTraceOpsLogo.png in the Assets folder to show it in the UI and reports." "INFO"
        return
    }

    try {
        $pictureBox = New-Object System.Windows.Forms.PictureBox
        $pictureBox.Location = New-Object System.Drawing.Point(965, 15)
        $pictureBox.Size = New-Object System.Drawing.Size(110, 110)
        $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pictureBox.BackColor = $Script:Theme.FormBack
        $pictureBox.Image = [System.Drawing.Image]::FromFile($Script:LogoPath)
        $Form.Controls.Add($pictureBox)
        Write-ToolLog "Logo loaded into UI from $Script:LogoPath" "SUCCESS"
    }
    catch {
        Write-ToolLog "Logo could not be loaded into UI: $($_.Exception.Message)" "WARN"
    }
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
    $btn.BackColor = $Script:Theme.ButtonBack
    $btn.ForeColor = $Script:Theme.ButtonFore
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderColor = $Script:Theme.Border
    $btn.FlatAppearance.BorderSize = 1
    $btn.UseVisualStyleBackColor = $false
    $btn.Add_MouseEnter({ $this.BackColor = $Script:Theme.ButtonHover })
    $btn.Add_MouseLeave({ $this.BackColor = $Script:Theme.ButtonBack })
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

function ConvertTo-ReportCardsHtml {
    param(
        [array]$Items,
        [string]$EmptyMessage = "No items were collected for this section.",
        [int]$MaxItems = 8
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return "<div class='empty-state'>$([System.Web.HttpUtility]::HtmlEncode($EmptyMessage))</div>"
    }

    $cards = foreach ($item in ($Items | Select-Object -First $MaxItems)) {
        $encoded = [System.Web.HttpUtility]::HtmlEncode([string]$item)
        "<div class='report-card'><div class='card-dot'></div><div class='card-text'>$encoded</div></div>"
    }

    if ($Items.Count -gt $MaxItems) {
        $remaining = $Items.Count - $MaxItems
        $cards += "<div class='report-card muted-card'><div class='card-dot'></div><div class='card-text'>+$remaining additional item(s) captured in the investigation output.</div></div>"
    }

    return "<div class='report-card-grid'>$($cards -join "`n")</div>"
}

function New-PivotDiagramHtml {
    param(
        [string[]]$Steps,
        [string]$Title = "Investigation Flow"
    )

    if (-not $Steps -or $Steps.Count -eq 0) {
        return ""
    }

    $stepHtml = for ($i = 0; $i -lt $Steps.Count; $i++) {
        $stepNumber = $i + 1
        $stepText = [System.Web.HttpUtility]::HtmlEncode($Steps[$i])
        $arrow = if ($i -lt ($Steps.Count - 1)) { "<div class='flow-arrow'>&rarr;</div>" } else { "" }
        "<div class='flow-step'><div class='flow-number'>$stepNumber</div><div class='flow-text'>$stepText</div></div>$arrow"
    }

    return @"
<div class='pivot-diagram'>
  <div class='pivot-title'>$Title</div>
  <div class='flow-row'>
    $($stepHtml -join "`n")
  </div>
</div>
"@
}

function ConvertTo-HtmlTableFromHashtable {
    param([hashtable]$Table)

    if (-not $Table -or $Table.Count -eq 0) {
        return "<p>No user summary details were collected.</p>"
    }

    $rows = foreach ($key in $Table.Keys) {
        $value = $Table[$key]
        "<tr><th>$([System.Web.HttpUtility]::HtmlEncode([string]$key))</th><td>$([System.Web.HttpUtility]::HtmlEncode([string]$value))</td></tr>"
    }

    return "<table>$($rows -join "`n")</table>"
}

function ConvertTo-ReportCardsHtml {
    param(
        [array]$Items,
        [string]$EmptyMessage = "No items were collected for this section.",
        [int]$PreviewCount = 8
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return "<div class='report-card muted-card'>$([System.Web.HttpUtility]::HtmlEncode($EmptyMessage))</div>"
    }

    $preview = @($Items | Select-Object -First $PreviewCount)
    $cards = foreach ($item in $preview) {
        "<div class='report-card'>$([System.Web.HttpUtility]::HtmlEncode([string]$item))</div>"
    }

    $remaining = $Items.Count - $preview.Count
    if ($remaining -gt 0) {
        $cards += "<div class='report-card more-card'>+$remaining additional item(s) captured. Open the detailed workflow report or JSON snapshot for full evidence.</div>"
    }

    return ($cards -join "`n")
}

function New-PivotDiagramHtml {
    param(
        [string]$Title,
        [array]$Steps
    )

    if (-not $Steps -or $Steps.Count -eq 0) { return "" }

    $stepHtml = foreach ($step in $Steps) {
        "<div class='flow-step'>$([System.Web.HttpUtility]::HtmlEncode([string]$step))</div>"
    }

    return @"
<div class='flow-panel'>
  <div class='flow-title'>$([System.Web.HttpUtility]::HtmlEncode($Title))</div>
  <div class='flow-grid'>
    $($stepHtml -join "<div class='flow-arrow'>&rarr;</div>")
  </div>
</div>
"@
}

function Set-CollectionStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    if ($Script:Investigation -and $Script:Investigation.CollectionStatus.Contains($Name)) {
        $Script:Investigation.CollectionStatus[$Name] = $Status
    }
}

function Export-InvestigationJson {
    
    if (-not (Test-CanExportShadowTraceReport)) { return $null }
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
        Save-AnalystWorkflowToInvestigation
        $upn = $Script:Investigation.UserPrincipalName
        $safeName = $upn.Replace("@", "_").Replace(".", "_").Replace("\", "_").Replace("/", "_")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $jsonFile = Join-Path $Script:ExportPath "ShadowTraceOps-Investigation-$safeName-$timestamp.json"

        $Script:Investigation | ConvertTo-Json -Depth 8 | Out-File -FilePath $jsonFile -Encoding UTF8
        Set-CollectionStatus -Name "JsonExport" -Status "Completed"
        Write-ToolLog "Investigation JSON snapshot exported: $jsonFile" "SUCCESS"
        Start-Process $Script:ExportPath
    }
    catch {
        Set-CollectionStatus -Name "JsonExport" -Status "Failed"
        Write-ToolLog "JSON export failed: $($_.Exception.Message)" "ERROR"
    }
}

function Convert-CollectionStatusToHtml {
    if (-not $Script:Investigation -or -not $Script:Investigation.CollectionStatus) {
        return "<p>No collection status was recorded.</p>"
    }

    $rows = foreach ($key in $Script:Investigation.CollectionStatus.Keys) {
        $value = $Script:Investigation.CollectionStatus[$key]
        "<tr><th>$([System.Web.HttpUtility]::HtmlEncode([string]$key))</th><td>$([System.Web.HttpUtility]::HtmlEncode([string]$value))</td></tr>"
    }

    return "<table>$($rows -join "`n")</table>"
}

function Initialize-InvestigationObject {
    param([string]$UserPrincipalName)

    $Script:Investigation = [ordered]@{
        ToolkitPhase        = "Phase 1"
        Mode                = "Read-only / Advisory"
        UserPrincipalName   = $UserPrincipalName
        StartTime           = Get-Date
        EndTime             = $null
        UserSummary         = [ordered]@{}
        IdentityRisk        = @()
        Authentication      = @()
        CloudActivity       = @()
        SessionBehavior     = @()
        OAuthActivity       = @()
        Alerts              = @()
        Incidents           = @()
        DlpVisibility       = @()
        EndpointContext     = @()
        EmailContext        = @()
        UrlClickContext     = @()
        CloudAppEvents      = @()
        UnifiedTimeline     = @()
        SourceHealth        = @()
        Capabilities        = [ordered]@{}
        ProductReadiness    = "Unknown"
        ObservedRisks       = @()
        PotentialGaps       = @()
        Recommendations     = @()
        InvestigationPivots = @()
        Priority            = "Review Required"
        AuthLookbackDays    = 7
        RunMode             = "Investigation"
        MaxQueryRows        = 10
        HuntingLookbackDays = 3
        InvestigationProfile = "Investigation 7d - Normal investigation"
        IsSummaryOnlyRun     = $false
        MaxCollectorRuntimeSeconds = 30
        RunId               = [guid]::NewGuid().ToString()
        CollectionStatus    = [ordered]@{
            UserResolution = "Not started"
            IdentityRisk   = "Not started"
            Authentication = "Not started"
            OAuthActivity  = "Not started"
            XdrAlerts      = "Not started"
            XdrIncidents    = "Not started"
            EndpointContext = "Not started"
            EmailContext    = "Not started"
            UrlClickContext = "Not started"
            CloudAppEvents  = "Not started"
            UnifiedTimeline = "Not started"
            CloudSession   = "Not started"
            ReportExport   = "Not started"
            JsonExport     = "Not started"
            SourceHealth    = "Not started"
        }
    }

    $Script:Investigation.AnalystNotes = ""
    $Script:Investigation.AnalystAssessment = ""
    $Script:Investigation.AnalystStatus = [ordered]@{}
    $Script:Investigation.AnalystTimeline = @()
}

# ------------------------------------------------------------
# Analysis Helper Functions
# ------------------------------------------------------------

function Add-UniqueInvestigationItem {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "IdentityRisk",
            "Authentication",
            "CloudActivity",
            "SessionBehavior",
            "OAuthActivity",
            "Alerts",
            "DlpVisibility",
            "ObservedRisks",
            "PotentialGaps",
            "Recommendations",
            "InvestigationPivots",
            "Incidents",
            "EndpointContext",
            "EmailContext",
            "UrlClickContext",
            "CloudAppEvents",
            "UnifiedTimeline",
            "SourceHealth"
        )]
        [string]$Section,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if (-not $Script:Investigation[$Section].Contains($Value)) {
        $Script:Investigation[$Section] += $Value
    }
}

function Get-SignInStatusText {
    param($SignIn)

    if ($SignIn.Status -and $SignIn.Status.ErrorCode -eq 0) {
        return "Success"
    }

    if ($SignIn.Status -and $SignIn.Status.FailureReason) {
        return "Failure/Interrupted - $($SignIn.Status.FailureReason)"
    }

    return "Failure/Interrupted"
}

function Get-SignInLocationText {
    param($SignIn)

    if ($SignIn.Location) {
        $parts = @(
            $SignIn.Location.City,
            $SignIn.Location.State,
            $SignIn.Location.CountryOrRegion
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        if ($parts.Count -gt 0) {
            return ($parts -join ", ")
        }
    }

    return "Unknown"
}

function Get-ConditionalAccessSummaryText {
    param($SignIn)

    if ($SignIn.ConditionalAccessStatus) {
        return $SignIn.ConditionalAccessStatus
    }

    return "Not available"
}

function Invoke-SignInPatternAssessment {
    param([array]$SignIns)

    if (-not $SignIns -or $SignIns.Count -eq 0) {
        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "No sign-in records were available for pattern assessment in this run."
        return
    }

    $successful = @($SignIns | Where-Object { $_.Status -and $_.Status.ErrorCode -eq 0 })
    $failed = @($SignIns | Where-Object { -not $_.Status -or $_.Status.ErrorCode -ne 0 })
    $risky = @($SignIns | Where-Object {
        ($_.RiskLevelAggregated -and $_.RiskLevelAggregated -ne "none") -or
        ($_.RiskLevelDuringSignIn -and $_.RiskLevelDuringSignIn -ne "none") -or
        ($_.RiskState -and $_.RiskState -ne "none")
    })
    $unmanagedOrUnknownDevice = @($SignIns | Where-Object {
        -not $_.DeviceDetail -or
        [string]::IsNullOrWhiteSpace($_.DeviceDetail.DeviceId) -or
        [string]::IsNullOrWhiteSpace($_.DeviceDetail.TrustType)
    })
    $uniqueIps = @($SignIns | Where-Object { $_.IpAddress } | Select-Object -ExpandProperty IpAddress -Unique)
    $uniqueApps = @($SignIns | Where-Object { $_.AppDisplayName } | Select-Object -ExpandProperty AppDisplayName -Unique)
    $uniqueCountries = @($SignIns | Where-Object { $_.Location -and $_.Location.CountryOrRegion } | ForEach-Object { $_.Location.CountryOrRegion } | Select-Object -Unique)

    Add-UniqueInvestigationItem -Section "Authentication" -Value "Sign-in summary: $($successful.Count) successful, $($failed.Count) failed/interrupted, $($risky.Count) with risk-related fields, $($uniqueIps.Count) unique IP(s), $($uniqueApps.Count) unique app(s), $($uniqueCountries.Count) unique country/region value(s)."

    if ($failed.Count -ge 5) {
        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "Multiple failed or interrupted sign-ins were observed in the selected lookback window. Review whether these indicate password spray, MFA fatigue, blocked attempts, or normal user error."
        Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Review failed/interrupted sign-ins by IP address, application, device, and Conditional Access result."
    }

    if ($risky.Count -gt 0) {
        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "One or more sign-in records included risk-related fields. Validate risk level, risk state, risk detail, and whether controls responded as expected."
        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Review whether risky sign-ins trigger appropriate Conditional Access, session controls, alerting, and response workflow."
    }

    if ($uniqueIps.Count -ge 5) {
        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "Multiple unique IP addresses were observed during the selected authentication lookback window. Review whether this aligns with expected user behavior."
    }

    if ($uniqueCountries.Count -ge 2) {
        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "Multiple country/region values were observed in sign-in activity. Review for impossible travel, VPN/proxy usage, or abnormal access patterns."
        Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Compare sign-in geography, timestamps, client apps, and device details for impossible or unlikely travel patterns."
    }

    if ($unmanagedOrUnknownDevice.Count -gt 0) {
        Add-UniqueInvestigationItem -Section "SessionBehavior" -Value "$($unmanagedOrUnknownDevice.Count) sign-in record(s) had missing, unknown, or unmanaged-looking device trust details. Validate device trust and session control coverage."
        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Review whether unmanaged or unknown device access is constrained by Conditional Access App Control session policies."
    }
}

function Invoke-IdentityRiskAssessment {
    param([array]$RiskDetections)

    if (-not $RiskDetections -or $RiskDetections.Count -eq 0) {
        return
    }

    $highRisk = @($RiskDetections | Where-Object { $_.RiskLevel -eq "high" })
    $mediumRisk = @($RiskDetections | Where-Object { $_.RiskLevel -eq "medium" })
    $riskTypes = @($RiskDetections | Where-Object { $_.RiskType } | Select-Object -ExpandProperty RiskType -Unique)

    Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "Identity risk detection summary: $($RiskDetections.Count) detection(s), $($highRisk.Count) high risk, $($mediumRisk.Count) medium risk, risk type(s): $($riskTypes -join ', ')."

    if ($highRisk.Count -gt 0) {
        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "High identity risk detection activity was present. Validate the user timeline and response actions before treating the session as trusted."
        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Review whether high identity risk produces alerting, Conditional Access enforcement, and documented analyst response steps."
        $Script:Investigation.Priority = "High - Prompt Analyst Review Recommended"
    }
    elseif ($mediumRisk.Count -gt 0 -and $Script:Investigation.Priority -ne "High - Prompt Analyst Review Recommended") {
        $Script:Investigation.Priority = "Medium - Analyst Review Recommended"
    }
}


function Get-AdvancedHuntingFailureClassification {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return "Unknown failure"
    }

    if ($Message -match "Forbidden|Authorization|Unauthorized|Access denied|permission|consent|401|403") {
        return "Permission or role access issue"
    }

    if ($Message -match "BadRequest|Syntax|semantic|parse|Invalid query|400") {
        return "Runtime KQL schema/table availability issue"
    }

    if ($Message -match "table|column|Failed to resolve|does not refer|Unknown") {
        return "Table or column unavailable in this tenant"
    }

    if ($Message -match "timeout|timed out|TooManyRequests|429|throttl") {
        return "Service throttling or timeout"
    }

    return "Unclassified Advanced Hunting failure"
}

function Add-SourceHealthItem {
    param(
        [string]$CollectorName,
        [string]$Status,
        [string]$Detail,
        [nullable[double]]$DurationSeconds = $null,
        [nullable[int]]$RowsReturned = $null
    )

    $durationText = if ($null -ne $DurationSeconds) { " | DurationSeconds=$DurationSeconds" } else { "" }
    $rowsText = if ($null -ne $RowsReturned) { " | RowsReturned=$RowsReturned" } else { "" }

    Add-UniqueInvestigationItem -Section "SourceHealth" -Value "$CollectorName | Status=$Status$rowsText$durationText | Detail=$Detail"
}

function Test-AdvancedHuntingTablePhase1 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [string]$CollectorName = $TableName
    )

    Write-ToolLog "Validating Advanced Hunting table availability for $TableName." "INFO"

    $validationQuery = @"
$TableName
| take 1
"@

    $result = Invoke-AdvancedHuntingQueryPhase1 -Query $validationQuery -CollectorName "$CollectorName TableValidation"

    if ($result -is [System.Collections.IDictionary] -and $result.Failed) {
        Add-SourceHealthItem -CollectorName "$CollectorName TableValidation" -Status "Failed" -RowsReturned 0 -Detail "Table validation failed. Classification: $($result.Classification). Error: $($result.ErrorMessage)"
        return [ordered]@{
            Available      = $false
            Classification = $result.Classification
            ErrorMessage   = $result.ErrorMessage
            Columns        = @()
        }
    }

    if ($result -and $result.Count -gt 0) {
        $columns = @($result[0].PSObject.Properties.Name)
        Add-SourceHealthItem -CollectorName "$CollectorName TableValidation" -Status "Available" -RowsReturned $result.Count -Detail "Table responded. Columns observed: $($columns -join ', ')"
        return [ordered]@{
            Available      = $true
            Classification = "Available"
            ErrorMessage   = $null
            Columns        = $columns
        }
    }

    Add-SourceHealthItem -CollectorName "$CollectorName TableValidation" -Status "Available - Empty" -RowsReturned 0 -Detail "Table query succeeded but returned no sample rows. Schema could not be inferred from sample data."
    return [ordered]@{
        Available      = $true
        Classification = "Available - Empty"
        ErrorMessage   = $null
        Columns        = @()
    }
}

function Test-ColumnPresencePhase1 {
    param(
        [array]$Columns,
        [array]$RequiredColumns
    )

    if (-not $RequiredColumns -or $RequiredColumns.Count -eq 0) {
        return [ordered]@{
            Valid          = $true
            MissingColumns = @()
        }
    }

    if (-not $Columns -or $Columns.Count -eq 0) {
        return [ordered]@{
            Valid          = $true
            MissingColumns = @()
        }
    }

    $missing = @($RequiredColumns | Where-Object { $_ -notin $Columns })

    return [ordered]@{
        Valid          = ($missing.Count -eq 0)
        MissingColumns = $missing
    }
}


function Add-RuntimeAdvancedHuntingAdvisory {
    param(
        [string]$CollectorName = "Advanced Hunting"
    )

    Add-SourceHealthItem -Collector $CollectorName -Status "Skipped" -Classification "Advisory / Runtime KQL disabled" -Detail "Runtime Advanced Hunting collectors are disabled by default in Phase 1 to avoid noisy permission/schema failures. KQL is still available in the JSON playbook side panel under Toolkit\Config\KQL."
}


function Invoke-AdvancedHuntingQueryPhase1 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [string]$CollectorName = "AdvancedHunting"
    )

    Write-ToolLog "Running Advanced Hunting query for $CollectorName." "INFO"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $body = @{ Query = $Query } | ConvertTo-Json -Depth 4

        # Microsoft Graph Security advanced hunting endpoint.
        # Requires ThreatHunting.Read.All with admin consent where applicable.
        $response = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/security/runHuntingQuery" -Body $body -ContentType "application/json" -ErrorAction Stop

        $stopwatch.Stop()
        $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

        if ($response -and $response.Results) {
            $rows = @($response.Results)
            Write-ToolLog "Advanced Hunting query for $CollectorName returned $($rows.Count) row(s) in $duration second(s)." "SUCCESS"
            Add-SourceHealthItem -CollectorName $CollectorName -Status "Completed" -RowsReturned $rows.Count -DurationSeconds $duration -Detail "Advanced Hunting query completed successfully."
            return $rows
        }

        Write-ToolLog "Advanced Hunting query for $CollectorName returned no rows in $duration second(s)." "INFO"
        Add-SourceHealthItem -CollectorName $CollectorName -Status "Completed - No records matched" -RowsReturned 0 -DurationSeconds $duration -Detail "Query completed but returned no matching records."
        return @()
    }
    catch {
        $stopwatch.Stop()
        $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
        $classification = Get-AdvancedHuntingFailureClassification -Message $_.Exception.Message

        Write-ToolLog "Advanced Hunting query failed for ${CollectorName}: $($_.Exception.Message)" "WARN"
        Write-ToolLog "Advanced Hunting failure classification for ${CollectorName}: $classification" "WARN"
        Write-ToolLog "Advanced Hunting runtime collection is optional in Phase 1. If enabled, it requires supported Defender XDR data, ThreatHunting.Read.All, and appropriate Defender role access. Playbook KQL remains available even when runtime collection is skipped." "WARN"

        Add-SourceHealthItem -CollectorName $CollectorName -Status "Failed" -RowsReturned 0 -DurationSeconds $duration -Detail "$classification. Raw error: $($_.Exception.Message)"
        return [ordered]@{
            Failed         = $true
            Classification = $classification
            ErrorMessage   = $_.Exception.Message
            Rows           = @()
        }
    }
}


function Add-EndpointRuntimeHuntingUnavailableAdvisory {
    param(
        [string]$Reason = "DeviceLogonEvents table/schema was not available or runtime endpoint hunting could not be completed."
    )

    Set-CollectionStatus -Name "EndpointContext" -Status "Telemetry unavailable - advisory"

    Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint runtime Advanced Hunting was not completed. Reason: $Reason"
    Add-UniqueInvestigationItem -Section "SourceHealth" -Value "EndpointContext: Telemetry unavailable or not validated. Impact: endpoint correlation depth is reduced. This does not confirm suspicious activity."
    Add-UniqueInvestigationItem -Section "Recommendations" -Value "If endpoint correlation is required, verify Microsoft Defender for Endpoint onboarding, Defender XDR role access, ThreatHunting.Read.All consent, and availability of DeviceLogonEvents in Advanced Hunting."

    Write-ToolLog "Endpoint runtime hunting unavailable/advisory: $Reason" "WARN"
}

function Test-EndpointAdvancedHuntingReadiness {
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $ctx) {
            return @{
                Ready = $false
                Reason = "Microsoft Graph context is not connected."
            }
        }

        if (@($ctx.Scopes) -notcontains "ThreatHunting.Read.All") {
            return @{
                Ready = $false
                Reason = "ThreatHunting.Read.All is not present in the current Graph context."
            }
        }

        $probeQuery = "DeviceLogonEvents | take 1"
        $body = @{ Query = $probeQuery } | ConvertTo-Json -Depth 5
        $null = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/security/runHuntingQuery" -Body $body -ContentType "application/json" -ErrorAction Stop

        return @{
            Ready = $true
            Reason = "DeviceLogonEvents probe completed."
        }
    }
    catch {
        $msg = $_.Exception.Message
        $reason = if ($msg -match "Forbidden|Unauthorized|403|permission|role") {
            "Permission or Defender XDR role access issue while probing DeviceLogonEvents."
        }
        elseif ($msg -match "DeviceLogonEvents|Failed to resolve|table|schema|semantic|BadRequest|400") {
            "DeviceLogonEvents table/schema is unavailable in this tenant or current hunting context."
        }
        elseif ($msg -match "429|throttl|timeout") {
            "Advanced Hunting probe was throttled or timed out."
        }
        else {
            "Advanced Hunting endpoint telemetry probe failed: $msg"
        }

        return @{
            Ready = $false
            Reason = $reason
        }
    }
}


function Get-EndpointContextPhase1 {
    
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    
    if (-not $Script:EnableRuntimeAdvancedHunting) {
        Set-CollectionStatus -Name "EndpointContext" -Status "Skipped - Runtime KQL disabled"
        Add-RuntimeAdvancedHuntingAdvisory -CollectorName "EndpointContext"
        return
    }

    $endpointReadiness = Test-EndpointAdvancedHuntingReadiness
    if (-not $endpointReadiness.Ready) {
        Add-EndpointRuntimeHuntingUnavailableAdvisory -Reason $endpointReadiness.Reason
        return
    }

Set-CollectionStatus -Name "EndpointContext" -Status "Running"
    Write-ToolLog "Collecting Phase 1 Defender for Endpoint context for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        $tableValidation = Test-AdvancedHuntingTablePhase1 -TableName "DeviceLogonEvents" -CollectorName "EndpointContext"
        if (-not $tableValidation.Available) {
            Add-UniqueInvestigationItem -Section "EndpointContext" -Value "DeviceLogonEvents table validation failed. Classification: $($tableValidation.Classification). Endpoint collector skipped."
            Set-CollectionStatus -Name "EndpointContext" -Status "Failed - $($tableValidation.Classification)"
            return
        }

        $columnCheck = Test-ColumnPresencePhase1 -Columns $tableValidation.Columns -RequiredColumns @("Timestamp", "AccountUpn", "AccountName", "DeviceName", "LogonType", "RemoteIP")
        if (-not $columnCheck.Valid) {
            Add-UniqueInvestigationItem -Section "EndpointContext" -Value "DeviceLogonEvents table is available, but expected columns were not observed: $($columnCheck.MissingColumns -join ', '). Endpoint query may need schema adjustment."
            Set-CollectionStatus -Name "EndpointContext" -Status "Failed - Runtime KQL schema/table availability issue"
            return
        }

        $safeUpn = $UserPrincipalName.Replace("'", "''")
        $query = @"
let TargetUser = '$safeUpn';
DeviceLogonEvents
| where Timestamp > ago($($LookbackDays)d)
| where AccountUpn =~ TargetUser or AccountName =~ split(TargetUser, '@')[0]
| summarize LastSeen=max(Timestamp), LogonCount=count(), Devices=dcount(DeviceName), DeviceNames=make_set(DeviceName, 10), LogonTypes=make_set(LogonType, 10), RemoteIPs=make_set(RemoteIP, 10) by AccountUpn
| take 25
"@

        $rows = Invoke-AdvancedHuntingQueryPhase1 -Query $query -CollectorName "EndpointContext"

        if ($rows -is [System.Collections.IDictionary] -and $rows.Failed) {
            Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint runtime Advanced Hunting was unavailable or not validated. Classification: $($rows.Classification). Review ThreatHunting.Read.All, Defender XDR role access, and availability of DeviceLogonEvents."
            Set-CollectionStatus -Name "EndpointContext" -Status "Failed - $($rows.Classification)"
            return
        }

        if ($rows.Count -gt 0) {
            foreach ($row in $rows) {
                Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint logon context: Account=$($row.AccountUpn) | LastSeen=$($row.LastSeen) | LogonCount=$($row.LogonCount) | Devices=$($row.Devices) | DeviceNames=$($row.DeviceNames -join ', ') | RemoteIPs=$($row.RemoteIPs -join ', ')"
            }
            Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Review endpoint device names from the Advanced Hunting results in Defender for Endpoint for alert timeline, exposure level, and logged-on user history."
            Set-CollectionStatus -Name "EndpointContext" -Status "Completed"
        }
        else {
            Add-UniqueInvestigationItem -Section "EndpointContext" -Value "No Defender for Endpoint DeviceLogonEvents were returned for this user in the selected lookback window."
            Set-CollectionStatus -Name "EndpointContext" -Status "Completed - No records matched"
        }

        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Review whether devices used for risky or unusual sign-ins are onboarded to Defender for Endpoint and covered by endpoint detection and response policies."
    }
    catch {
        Set-CollectionStatus -Name "EndpointContext" -Status "Telemetry unavailable - advisory"
        Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint context collection could not be completed. Review Defender XDR access, advanced hunting availability, and endpoint permissions."
        Write-ToolLog "Endpoint context collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-EmailPhishingContextPhase1 {
    
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    
    if (-not $Script:EnableRuntimeAdvancedHunting) {
        Set-CollectionStatus -Name "EmailContext" -Status "Skipped - Runtime KQL disabled"
        Add-RuntimeAdvancedHuntingAdvisory -CollectorName "EmailContext"
        return
    }
Set-CollectionStatus -Name "EmailContext" -Status "Running"
    Write-ToolLog "Collecting Phase 1 Defender for Office 365 email/phishing context for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        $safeUpn = $UserPrincipalName.Replace("'", "''")
        $query = @"
let TargetUser = '$safeUpn';
EmailEvents
| where Timestamp > ago($($LookbackDays)d)
| where RecipientEmailAddress =~ TargetUser
| summarize LastEmail=max(Timestamp), EmailCount=count(), ThreatTypes=make_set(ThreatTypes, 10), DeliveryActions=make_set(DeliveryAction, 10), Senders=make_set(SenderFromAddress, 10), Subjects=make_set(Subject, 10) by RecipientEmailAddress
| take 25
"@

        $rows = Invoke-AdvancedHuntingQueryPhase1 -Query $query -CollectorName "EmailContext"

        if ($rows -is [System.Collections.IDictionary] -and $rows.Failed) {
            Add-UniqueInvestigationItem -Section "EmailContext" -Value "Email Advanced Hunting query could not be completed. Classification: $($rows.Classification). Review ThreatHunting.Read.All, Defender XDR role access, and availability of EmailEvents."
            Set-CollectionStatus -Name "EmailContext" -Status "Failed - $($rows.Classification)"
            return
        }

        if ($rows.Count -gt 0) {
            foreach ($row in $rows) {
                Add-UniqueInvestigationItem -Section "EmailContext" -Value "Email context: Recipient=$($row.RecipientEmailAddress) | LastEmail=$($row.LastEmail) | EmailCount=$($row.EmailCount) | ThreatTypes=$($row.ThreatTypes -join ', ') | DeliveryActions=$($row.DeliveryActions -join ', ') | Senders=$($row.Senders -join ', ')"
            }
            Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Review Defender for Office 365 email events, URL clicks, attachment events, submissions, and mailbox audit activity for the same user and timeframe."
            Set-CollectionStatus -Name "EmailContext" -Status "Completed"
        }
        else {
            Add-UniqueInvestigationItem -Section "EmailContext" -Value "No Defender for Office 365 EmailEvents were returned for this user in the selected lookback window."
            Set-CollectionStatus -Name "EmailContext" -Status "Completed - No records matched"
        }

        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Review whether phishing-related detections are correlated with identity risk, sign-in risk, OAuth consent, and cloud activity during investigations."
    }
    catch {
        Set-CollectionStatus -Name "EmailContext" -Status "Failed"
        Add-UniqueInvestigationItem -Section "EmailContext" -Value "Email/phishing context collection could not be completed. Review Defender for Office 365 visibility, advanced hunting availability, and required permissions."
        Write-ToolLog "Email/phishing context collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-UrlClickContextPhase1 {
    
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    
    if (-not $Script:EnableRuntimeAdvancedHunting) {
        Set-CollectionStatus -Name "UrlClickContext" -Status "Skipped - Runtime KQL disabled"
        Add-RuntimeAdvancedHuntingAdvisory -CollectorName "UrlClickContext"
        return
    }
Set-CollectionStatus -Name "UrlClickContext" -Status "Running"
    Write-ToolLog "Collecting Phase 1 Defender for Office 365 URL click context for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        $safeUpn = $UserPrincipalName.Replace("'", "''")
        $query = @"
let TargetUser = '$safeUpn';
UrlClickEvents
| where Timestamp > ago($($LookbackDays)d)
| where AccountUpn =~ TargetUser
| summarize LastClick=max(Timestamp), ClickCount=count(), Actions=make_set(ActionType, 10), Urls=make_set(Url, 10), Workloads=make_set(Workload, 10) by AccountUpn
| take 25
"@

        $rows = Invoke-AdvancedHuntingQueryPhase1 -Query $query -CollectorName "UrlClickContext"

        if ($rows -is [System.Collections.IDictionary] -and $rows.Failed) {
            Add-UniqueInvestigationItem -Section "UrlClickContext" -Value "URL click Advanced Hunting query could not be completed. Classification: $($rows.Classification). Review ThreatHunting.Read.All, Defender XDR role access, and availability of UrlClickEvents."
            Set-CollectionStatus -Name "UrlClickContext" -Status "Failed - $($rows.Classification)"
            return
        }

        if ($rows.Count -gt 0) {
            foreach ($row in $rows) {
                Add-UniqueInvestigationItem -Section "UrlClickContext" -Value "URL click context: Account=$($row.AccountUpn) | LastClick=$($row.LastClick) | ClickCount=$($row.ClickCount) | Actions=$($row.Actions -join ', ') | Workloads=$($row.Workloads -join ', ') | Urls=$($row.Urls -join ', ')"
            }
            Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "URL click activity exists for this user in the selected lookback window. Review whether any clicks preceded suspicious authentication or cloud activity."
            Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Review URL click events for Safe Links action, clicked URL, delivery email, timestamp, and proximity to authentication events."
            Set-CollectionStatus -Name "UrlClickContext" -Status "Completed"
        }
        else {
            Add-UniqueInvestigationItem -Section "UrlClickContext" -Value "No Defender for Office 365 UrlClickEvents were returned for this user in the selected lookback window."
            Set-CollectionStatus -Name "UrlClickContext" -Status "Completed - No records matched"
        }
    }
    catch {
        Set-CollectionStatus -Name "UrlClickContext" -Status "Failed"
        Add-UniqueInvestigationItem -Section "UrlClickContext" -Value "URL click context collection could not be completed. Review Defender for Office 365 visibility, Advanced Hunting availability, and required permissions."
        Write-ToolLog "URL click context collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-CloudAppEventsContextPhase1 {
    
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    
    if (-not $Script:EnableRuntimeAdvancedHunting) {
        Set-CollectionStatus -Name "CloudAppEvents" -Status "Skipped - Runtime KQL disabled"
        Add-RuntimeAdvancedHuntingAdvisory -CollectorName "CloudAppEvents"
        return
    }
Set-CollectionStatus -Name "CloudAppEvents" -Status "Running"
    Write-ToolLog "Collecting Phase 1 Defender for Cloud Apps event context for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        $tableValidation = Test-AdvancedHuntingTablePhase1 -TableName "CloudAppEvents" -CollectorName "CloudAppEvents"
        if (-not $tableValidation.Available) {
            Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "CloudAppEvents table validation failed. Classification: $($tableValidation.Classification). Cloud app collector skipped."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Failed - $($tableValidation.Classification)"
            return
        }

        $columnCheck = Test-ColumnPresencePhase1 -Columns $tableValidation.Columns -RequiredColumns @("Timestamp", "AccountUpn", "ActionType")
        if (-not $columnCheck.Valid) {
            Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "CloudAppEvents table is available, but expected columns were not observed: $($columnCheck.MissingColumns -join ', '). Cloud app query may need schema adjustment."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Failed - Runtime KQL schema/table availability issue"
            return
        }

        $safeUpn = $UserPrincipalName.Replace("'", "''")
        $query = @"
let TargetUser = '$safeUpn';
CloudAppEvents
| where Timestamp > ago($($LookbackDays)d)
| where AccountUpn =~ TargetUser or AccountDisplayName =~ TargetUser
| summarize LastActivity=max(Timestamp), ActivityCount=count(), Apps=make_set(Application, 10), Actions=make_set(ActionType, 10), IPs=make_set(IPAddress, 10), Countries=make_set(CountryCode, 10) by AccountUpn
| take 25
"@

        $rows = Invoke-AdvancedHuntingQueryPhase1 -Query $query -CollectorName "CloudAppEvents"

        if ($rows -is [System.Collections.IDictionary] -and $rows.Failed) {
            Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "Cloud App Events Advanced Hunting query could not be completed. Classification: $($rows.Classification). Review ThreatHunting.Read.All, Defender XDR role access, and availability of CloudAppEvents."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Failed - $($rows.Classification)"
            return
        }

        if ($rows.Count -gt 0) {
            foreach ($row in $rows) {
                Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "Cloud app context: Account=$($row.AccountUpn) | LastActivity=$($row.LastActivity) | ActivityCount=$($row.ActivityCount) | Apps=$($row.Apps -join ', ') | Actions=$($row.Actions -join ', ') | IPs=$($row.IPs -join ', ') | Countries=$($row.Countries -join ', ')"
            }
            Add-UniqueInvestigationItem -Section "CloudActivity" -Value "CloudAppEvents returned activity for the user in the selected lookback window. Review actions, applications, IPs, countries, and activity volume against authentication context."
            Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Review CloudAppEvents around successful sign-ins for downloads, uploads, sharing, OAuth activity, unusual application use, and unmanaged session behavior."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Completed"
        }
        else {
            Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "No CloudAppEvents were returned for this user in the selected lookback window."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Completed - No records matched"
        }
    }
    catch {
        Set-CollectionStatus -Name "CloudAppEvents" -Status "Failed"
        Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "Cloud app event context collection could not be completed. Review Defender for Cloud Apps visibility, Advanced Hunting availability, and required permissions."
        Write-ToolLog "Cloud app event context collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Build-UnifiedTimelinePhase1 {
    Set-CollectionStatus -Name "UnifiedTimeline" -Status "Running"
    Write-ToolLog "Building Phase 1 unified investigation timeline." "INFO"

    try {
        Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Timeline anchor: Investigation started at $($Script:Investigation.StartTime)."

        foreach ($item in $Script:Investigation.IdentityRisk) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Identity Risk: $item"
        }

        foreach ($item in $Script:Investigation.Authentication) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Authentication: $item"
        }

        foreach ($item in $Script:Investigation.OAuthActivity) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "OAuth/App: $item"
        }

        foreach ($item in $Script:Investigation.Alerts) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "XDR Alert: $item"
        }

        foreach ($item in $Script:Investigation.Incidents) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "XDR Incident: $item"
        }

        foreach ($item in $Script:Investigation.EndpointContext) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Endpoint Context: $item"
        }

        foreach ($item in $Script:Investigation.EmailContext) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Email Context: $item"
        }

        foreach ($item in $Script:Investigation.UrlClickContext) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "URL Click Context: $item"
        }

        foreach ($item in $Script:Investigation.CloudAppEvents) {
            Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Cloud App Event: $item"
        }

        Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Timeline note: Phase 1 timeline is correlation-oriented and should be validated by the analyst against source portals and raw events."
        Set-CollectionStatus -Name "UnifiedTimeline" -Status "Completed"
    }
    catch {
        Set-CollectionStatus -Name "UnifiedTimeline" -Status "Failed"
        Add-UniqueInvestigationItem -Section "UnifiedTimeline" -Value "Unified timeline build failed. Review prior collector output and script logs."
        Write-ToolLog "Unified timeline build failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-OAuthAppActivityPhase1 {
    param(
        [string]$UserId,
        [string]$UserPrincipalName
    )

    Set-CollectionStatus -Name "OAuthActivity" -Status "Running"
    Write-ToolLog "Collecting Phase 1 OAuth and application activity indicators." "INFO"

    if (-not $UserId) {
        Add-UniqueInvestigationItem -Section "OAuthActivity" -Value "OAuth/app activity collection skipped because the user could not be resolved to an object ID."
        Write-ToolLog "OAuth/app activity collection skipped because no user object ID is available." "WARN"
        Set-CollectionStatus -Name "OAuthActivity" -Status "Skipped"
        return
    }

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop

        # Phase 1 advisory approach:
        # Enumerate OAuth2 permission grants where the user is the principal.
        # This is read-only and intended to identify grants that may need analyst review.
        $grants = @(Get-MgUserOauth2PermissionGrant -UserId $UserId -All -ErrorAction Stop)

        if ($grants -and $grants.Count -gt 0) {
            Add-UniqueInvestigationItem -Section "OAuthActivity" -Value "OAuth delegated permission grants found for this user: $($grants.Count). Review client apps, scopes, consent timing, and whether grants align with expected business use."

            foreach ($grant in ($grants | Select-Object -First 20)) {
                $scope = if ($grant.Scope) { $grant.Scope } else { "No scope returned" }
                Add-UniqueInvestigationItem -Section "OAuthActivity" -Value "OAuth grant: ClientId=$($grant.ClientId) | ResourceId=$($grant.ResourceId) | ConsentType=$($grant.ConsentType) | Scope=$scope"
            }

            $highInterestScopes = @("Mail.Read", "Mail.ReadWrite", "Files.Read", "Files.Read.All", "Files.ReadWrite", "Files.ReadWrite.All", "offline_access", "Directory.Read.All", "User.Read.All")
            $scopeText = ($grants | Where-Object { $_.Scope } | Select-Object -ExpandProperty Scope) -join " "
            $matchedScopes = @($highInterestScopes | Where-Object { $scopeText -match [regex]::Escape($_) })

            if ($matchedScopes.Count -gt 0) {
                Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "OAuth grants include high-interest scopes that may warrant review: $($matchedScopes -join ', '). Validate business need and consent source."
                Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Review whether OAuth app consent and high-impact delegated permissions are governed, monitored, and periodically reviewed."
                Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Review OAuth client IDs from this report against enterprise applications, sign-in logs, audit logs, and app governance findings."
            }
        }
        else {
            Add-UniqueInvestigationItem -Section "OAuthActivity" -Value "No OAuth delegated permission grants were returned for this user in the Phase 1 query."
            Write-ToolLog "No OAuth delegated permission grants returned for $UserPrincipalName." "INFO"
            Set-CollectionStatus -Name "OAuthActivity" -Status "Completed - No records matched"
        }
            if ($Script:Investigation.CollectionStatus.OAuthActivity -eq "Running") {
            Set-CollectionStatus -Name "OAuthActivity" -Status "Completed"
        }
    }
    catch {
        Set-CollectionStatus -Name "OAuthActivity" -Status "Failed"
        Add-UniqueInvestigationItem -Section "OAuthActivity" -Value "OAuth/app activity collection could not be completed. Review Graph permissions, module availability, and whether user OAuth grant enumeration is available in this tenant."
        Write-ToolLog "OAuth/app activity collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-XdrIncidentContextPhase1 {
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    Set-CollectionStatus -Name "XdrIncidents" -Status "Running"
    Write-ToolLog "Collecting Phase 1 Defender XDR incident context for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        Import-Module Microsoft.Graph.Security -ErrorAction Stop

        $startTime = (Get-Date).AddDays(-$LookbackDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $incidents = @(Get-MgSecurityIncident -Filter "createdDateTime ge $startTime" -Top 50 -ErrorAction Stop)

        $matchedIncidents = @($incidents | Where-Object {
            ($_.AssignedTo -and $_.AssignedTo -match [regex]::Escape($UserPrincipalName)) -or
            ($_.Description -and $_.Description -match [regex]::Escape($UserPrincipalName)) -or
            ($_.DisplayName -and $_.DisplayName -match [regex]::Escape($UserPrincipalName)) -or
            ($_.Summary -and $_.Summary -match [regex]::Escape($UserPrincipalName))
        })

        if ($matchedIncidents -and $matchedIncidents.Count -gt 0) {
            Add-UniqueInvestigationItem -Section "Incidents" -Value "Defender XDR/Security incident context returned $($matchedIncidents.Count) incident(s) that appear related to this user in the selected lookback window."

            foreach ($incident in ($matchedIncidents | Select-Object -First 15)) {
                Add-UniqueInvestigationItem -Section "Incidents" -Value "Incident: $($incident.CreatedDateTime) | Severity=$($incident.Severity) | Status=$($incident.Status) | Name=$($incident.DisplayName)"
            }

            $highIncidents = @($matchedIncidents | Where-Object { $_.Severity -eq "high" })
            if ($highIncidents.Count -gt 0) {
                $Script:Investigation.Priority = "High - Prompt Analyst Review Recommended"
                Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "High severity Defender XDR/Security incident context appears related to this user. Correlate incident timing with authentication, OAuth, and cloud activity."
                Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Open the related Defender XDR incident and review users, entities, evidence, timeline, and linked alerts."
            }
        }
        else {
            Add-UniqueInvestigationItem -Section "Incidents" -Value "No Defender XDR/Security incidents were matched to this user in the Phase 1 query."
            Write-ToolLog "No Defender XDR/Security incidents matched to $UserPrincipalName in the last $LookbackDays day(s)." "INFO"
        }

        Set-CollectionStatus -Name "XdrIncidents" -Status "Completed"
    }
    catch {
        Set-CollectionStatus -Name "XdrIncidents" -Status "Failed"
        Add-UniqueInvestigationItem -Section "Incidents" -Value "Defender XDR/Security incident context collection could not be completed. Review SecurityIncident.Read.All, admin consent, Graph Security API availability, and module support."
        Write-ToolLog "Defender XDR/Security incident collection failed: $($_.Exception.Message)" "WARN"
        Write-ToolLog "XDR incident collection usually requires SecurityIncident.Read.All with admin consent." "WARN"
    }
}

function Get-XdrAlertContextPhase1 {
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    Set-CollectionStatus -Name "XdrAlerts" -Status "Running"
    Write-ToolLog "Collecting Phase 1 Defender XDR alert context for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        Import-Module Microsoft.Graph.Security -ErrorAction Stop

        $startTime = (Get-Date).AddDays(-$LookbackDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Security alerts can vary by tenant and API availability. Phase 1 uses a broad filter and then narrows by user text.
        $alerts = @(Get-MgSecurityAlertV2 -Filter "createdDateTime ge $startTime" -Top 50 -ErrorAction Stop)
        $matchedAlerts = @($alerts | Where-Object {
            ($_.UserStates -and ($_.UserStates | Out-String) -match [regex]::Escape($UserPrincipalName)) -or
            ($_.Evidence -and ($_.Evidence | Out-String) -match [regex]::Escape($UserPrincipalName)) -or
            ($_.Description -and $_.Description -match [regex]::Escape($UserPrincipalName)) -or
            ($_.Title -and $_.Title -match [regex]::Escape($UserPrincipalName))
        })

        if ($matchedAlerts -and $matchedAlerts.Count -gt 0) {
            Add-UniqueInvestigationItem -Section "Alerts" -Value "Defender XDR/Security alert context returned $($matchedAlerts.Count) alert(s) that appear related to this user in the selected lookback window."

            foreach ($alert in ($matchedAlerts | Select-Object -First 15)) {
                Add-UniqueInvestigationItem -Section "Alerts" -Value "Alert: $($alert.CreatedDateTime) | Severity=$($alert.Severity) | Status=$($alert.Status) | Title=$($alert.Title) | Category=$($alert.Category)"
            }

            $highAlerts = @($matchedAlerts | Where-Object { $_.Severity -eq "high" })
            if ($highAlerts.Count -gt 0) {
                $Script:Investigation.Priority = "High - Prompt Analyst Review Recommended"
                Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "High severity Defender XDR/Security alert context appears related to this user. Correlate alert timing with authentication and cloud activity."
                Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Open the related Defender XDR incident or alert and pivot on user, device, app, IP, file, and OAuth evidence."
            }
        }
        else {
            Add-UniqueInvestigationItem -Section "Alerts" -Value "No Defender XDR/Security alerts were matched to this user in the Phase 1 query."
            Write-ToolLog "No Defender XDR/Security alerts matched to $UserPrincipalName in the last $LookbackDays day(s)." "INFO"
            Set-CollectionStatus -Name "XdrAlerts" -Status "Completed - No records matched"
        }
            if ($Script:Investigation.CollectionStatus.XdrAlerts -eq "Running") {
            Set-CollectionStatus -Name "XdrAlerts" -Status "Completed"
        }
    }
    catch {
        Set-CollectionStatus -Name "XdrAlerts" -Status "Failed"
        Add-UniqueInvestigationItem -Section "Alerts" -Value "Defender XDR/Security alert context collection could not be completed. Review SecurityAlert.Read.All, SecurityIncident.Read.All, SecurityEvents.Read.All, admin consent, Graph Security API availability, and module support."
        Write-ToolLog "Defender XDR/Security alert collection failed: $($_.Exception.Message)" "WARN"
        Write-ToolLog "XDR alert collection usually requires SecurityAlert.Read.All and/or SecurityIncident.Read.All with admin consent." "WARN"
    }
}

function Invoke-CloudSessionGapAssessmentPhase1 {
    Write-ToolLog "Running Phase 1 cloud/session defensive gap assessment." "INFO"

    $hasAuthData = ($Script:Investigation.Authentication.Count -gt 0)
    $hasRiskData = ($Script:Investigation.IdentityRisk.Count -gt 0)
    $hasOAuthData = ($Script:Investigation.OAuthActivity.Count -gt 0)
    $hasAlertData = ($Script:Investigation.Alerts.Count -gt 0)

    if ($hasAuthData -and $Script:chkSession.Checked) {
        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Validate whether successful authentication from unknown, unmanaged, or risky contexts is monitored or restricted by session controls."
        Add-UniqueInvestigationItem -Section "Recommendations" -Value "Review Conditional Access App Control session policies for monitor-only, block download, protect download, and real-time session control coverage."
    }

    if ($hasRiskData -and $Script:chkCloud.Checked) {
        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Validate whether identity risk is correlated with cloud activity such as mass downloads, external sharing, OAuth use, and unusual file access."
        Add-UniqueInvestigationItem -Section "Recommendations" -Value "Correlate risky user and risky sign-in windows with Defender for Cloud Apps activity timelines."
    }

    if ($hasOAuthData) {
        Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "Validate whether OAuth grants are reviewed alongside user risk and post-authentication activity during investigations."
    }

    if ($hasAlertData) {
        Add-UniqueInvestigationItem -Section "Recommendations" -Value "Use Defender XDR alert evidence as the anchor timeline and compare authentication, OAuth, cloud activity, and DLP visibility around the same timeframe."
    }

    Add-UniqueInvestigationItem -Section "DlpVisibility" -Value "Phase 1 does not yet pull live DLP events. Analysts should manually verify whether DLP or information protection events exist for the same user and timeframe."
    Add-UniqueInvestigationItem -Section "PotentialGaps" -Value "If large data movement is observed without matching DLP, audit, or MDCA visibility, review data protection coverage for the affected cloud apps and sensitive information types."
    Set-CollectionStatus -Name "CloudSession" -Status "Completed"
}

# ------------------------------------------------------------
# Connection / Collection Functions
# ------------------------------------------------------------


function Test-ThreatHuntingPermissionContext {
    try {
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $ctx) {
            Add-SourceHealthItem -Collector "Advanced Hunting Permission" -Status "Not Connected" -Classification "Graph not connected" -Detail "Connect to Microsoft Graph before running runtime Advanced Hunting collectors."
            return
        }

        $scopes = @($ctx.Scopes)
        if ($scopes -notcontains "ThreatHunting.Read.All") {
            Add-SourceHealthItem -Collector "Advanced Hunting Permission" -Status "Review" -Classification "Missing Graph scope" -Detail "ThreatHunting.Read.All was not present in the current Graph context. Reconnect with the required scope if runtime hunting is needed."
        }
        else {
            Add-SourceHealthItem -Collector "Advanced Hunting Permission" -Status "Available" -Classification "Graph scope present" -Detail "ThreatHunting.Read.All is present. Defender portal RBAC and table availability may still affect runtime hunting."
        }
    }
    catch {
        Add-SourceHealthItem -Collector "Advanced Hunting Permission" -Status "Review" -Classification "Permission check failed" -Detail $_.Exception.Message
    }
}


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
            "SecurityEvents.Read.All",
            "SecurityAlert.Read.All",
            "SecurityIncident.Read.All",
            "ThreatHunting.Read.All"
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

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        Stop-UnresolvedTargetUser -UserPrincipalName "<blank>" -Reason "A user principal name is required."
    }

    $Script:TargetUserResolved = $false
    $Script:LastResolvedUserPrincipalName = $null

    Set-CollectionStatus -Name "UserResolution" -Status "Running"
    Write-ToolLog "Resolving target user: $UserPrincipalName" "INFO"

    try {
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        $user = Get-MgUser -UserId $UserPrincipalName -Property "id,displayName,userPrincipalName,mail,accountEnabled,createdDateTime,userType,department,jobTitle" -ErrorAction Stop

        if ($null -eq $user) {
            Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason "Microsoft Graph returned no user object."
        }

        if ([string]::IsNullOrWhiteSpace($user.Id) -or [string]::IsNullOrWhiteSpace($user.UserPrincipalName)) {
            Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason "Microsoft Graph returned an incomplete user object."
        }

        $Script:TargetUserResolved = $true
        $Script:LastResolvedUserPrincipalName = $user.UserPrincipalName

        $Script:Investigation.UserPrincipalName = $user.UserPrincipalName
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
        Set-CollectionStatus -Name "UserResolution" -Status "Completed"
        return $user
    }
    catch {
        if ($_.Exception.Message -match "USER_RESOLUTION_FAILED") {
            throw
        }

        Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason $_.Exception.Message
    }
}

function Get-IdentityRiskPhase1 {
    param(
        [string]$UserId,
        [string]$UserPrincipalName
    )

    Set-CollectionStatus -Name "IdentityRisk" -Status "Running"
    Write-ToolLog "Collecting Entra ID risky user and risk detection information." "INFO"

    try {
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

        $foundRiskData = $false

        if ($UserId) {
            try {
                $riskyUser = Get-MgRiskyUser -RiskyUserId $UserId -ErrorAction Stop
                if ($riskyUser) {
                    $foundRiskData = $true
                    Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "Risky user record found. Risk level: $($riskyUser.RiskLevel). Risk state: $($riskyUser.RiskState). Risk detail: $($riskyUser.RiskDetail)."
                    Write-ToolLog "Risky user record found for $UserPrincipalName." "SUCCESS"

                    if ($riskyUser.RiskLevel -eq "high") {
                        $Script:Investigation.Priority = "High - Prompt Analyst Review Recommended"
                        Add-UniqueInvestigationItem -Section "ObservedRisks" -Value "The user is currently represented as high risk in Entra ID risky user data. Validate recent authentication and cloud activity before trusting active sessions."
                    }
                    elseif ($riskyUser.RiskLevel -eq "medium" -and $Script:Investigation.Priority -ne "High - Prompt Analyst Review Recommended") {
                        $Script:Investigation.Priority = "Medium - Analyst Review Recommended"
                    }
                }
            }
            catch {
                Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "No risky user record was returned, or the tenant/license/permissions did not allow risky user retrieval."
                Write-ToolLog "Risky user lookup did not return a record or failed: $($_.Exception.Message)" "WARN"
            }
        }

        try {
            $filter = "userPrincipalName eq '$UserPrincipalName'"
            $detections = @(Get-MgRiskDetection -Filter $filter -Top 25 -ErrorAction Stop)

            if ($detections -and $detections.Count -gt 0) {
                $foundRiskData = $true
                foreach ($detection in $detections) {
                    Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "Risk detection: $($detection.RiskType) | Level: $($detection.RiskLevel) | State: $($detection.RiskState) | Detected: $($detection.DetectedDateTime)"
                }
                Write-ToolLog "Collected $($detections.Count) identity risk detection record(s)." "SUCCESS"
                Invoke-IdentityRiskAssessment -RiskDetections $detections
            }
            else {
                Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "No identity risk detections were returned for this user in the initial Phase 1 query."
                Write-ToolLog "No identity risk detections returned for $UserPrincipalName." "INFO"
            }
        }
        catch {
            Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "Risk detection collection could not be completed. Review permissions, licensing, and Graph availability."
            Write-ToolLog "Risk detection collection failed: $($_.Exception.Message)" "WARN"
        }

        if ($foundRiskData) {
            Set-CollectionStatus -Name "IdentityRisk" -Status "Completed"
        }
        else {
            Set-CollectionStatus -Name "IdentityRisk" -Status "Completed - No records matched"
        }
    }
    catch {
        Add-UniqueInvestigationItem -Section "IdentityRisk" -Value "Microsoft.Graph.Identity.SignIns module was unavailable or could not be imported."
        Write-ToolLog "Identity risk module import failed: $($_.Exception.Message)" "ERROR"
        Set-CollectionStatus -Name "IdentityRisk" -Status "Failed"
    }
}

function Get-SignInActivityPhase1 {
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

    Set-CollectionStatus -Name "Authentication" -Status "Running"
    Write-ToolLog "Collecting recent sign-in activity for $UserPrincipalName. Lookback: $LookbackDays day(s)." "INFO"

    try {
        Import-Module Microsoft.Graph.Reports -ErrorAction Stop

        $startTime = (Get-Date).AddDays(-$LookbackDays).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $filter = "userPrincipalName eq '$UserPrincipalName' and createdDateTime ge $startTime"

        Write-ToolLog "Sign-in query filter: $filter" "INFO"
        $signIns = @(Get-MgAuditLogSignIn -Filter $filter -Top 50 -ErrorAction Stop)

        if ($signIns -and $signIns.Count -gt 0) {
            foreach ($signIn in $signIns) {
                $status = Get-SignInStatusText -SignIn $signIn
                $caStatus = Get-ConditionalAccessSummaryText -SignIn $signIn
                $app = if ($signIn.AppDisplayName) { $signIn.AppDisplayName } else { "Unknown app" }
                $ip = if ($signIn.IpAddress) { $signIn.IpAddress } else { "Unknown IP" }
                $location = Get-SignInLocationText -SignIn $signIn
                $clientApp = if ($signIn.ClientAppUsed) { $signIn.ClientAppUsed } else { "Unknown client" }
                $deviceTrust = if ($signIn.DeviceDetail -and $signIn.DeviceDetail.TrustType) { $signIn.DeviceDetail.TrustType } else { "Unknown/unmanaged" }
                $browser = if ($signIn.DeviceDetail -and $signIn.DeviceDetail.Browser) { $signIn.DeviceDetail.Browser } else { "Unknown browser" }
                $os = if ($signIn.DeviceDetail -and $signIn.DeviceDetail.OperatingSystem) { $signIn.DeviceDetail.OperatingSystem } else { "Unknown OS" }
                $risk = "RiskLevelAggregated=$($signIn.RiskLevelAggregated); RiskLevelDuringSignIn=$($signIn.RiskLevelDuringSignIn); RiskState=$($signIn.RiskState); RiskDetail=$($signIn.RiskDetail)"

                $authEntry = "{0} | {1} | App: {2} | Client: {3} | IP: {4} | Location: {5} | DeviceTrust: {6} | OS: {7} | Browser: {8} | CA: {9} | {10}" -f `
                    $signIn.CreatedDateTime,
                    $status,
                    $app,
                    $clientApp,
                    $ip,
                    $location,
                    $deviceTrust,
                    $os,
                    $browser,
                    $caStatus,
                    $risk

                Add-UniqueInvestigationItem -Section "Authentication" -Value $authEntry
            }

            Write-ToolLog "Collected $($signIns.Count) recent sign-in record(s) for the last $LookbackDays day(s)." "SUCCESS"
            Invoke-SignInPatternAssessment -SignIns $signIns
            Set-CollectionStatus -Name "Authentication" -Status "Completed"
        }
        else {
            Add-UniqueInvestigationItem -Section "Authentication" -Value "No recent sign-in records were returned for this user in the initial $LookbackDays-day Phase 1 query."
            Write-ToolLog "No recent sign-in records returned for $UserPrincipalName in the last $LookbackDays day(s)." "INFO"
            Set-CollectionStatus -Name "Authentication" -Status "Completed - No records matched"
        }
    }
    catch {
        Add-UniqueInvestigationItem -Section "Authentication" -Value "Sign-in collection could not be completed. Review AuditLog.Read.All, Reports.Read.All, tenant retention, and Graph module availability."
        Write-ToolLog "Sign-in collection failed: $($_.Exception.Message)" "WARN"
        Set-CollectionStatus -Name "Authentication" -Status "Failed"
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


function Initialize-CapabilityMatrix {
    if (-not $Script:Investigation) { return }

    $Script:Investigation.Capabilities = [ordered]@{
        EntraIdRisk          = $false
        SignInLogs           = $false
        DefenderXdr          = $false
        AdvancedHunting      = $false
        DefenderForEndpoint  = $false
        DefenderForOffice365 = $false
        DefenderForCloudApps = $false
        OAuthVisibility      = $false
        DlpVisibility        = $false
    }

    $Script:Investigation.ProductReadiness = "Unknown"
}

function Set-Capability {
    param(
        [string]$Name,
        [bool]$Enabled
    )

    if ($Script:Investigation -and $Script:Investigation.Capabilities -and $Script:Investigation.Capabilities.Contains($Name)) {
        $Script:Investigation.Capabilities[$Name] = $Enabled
    }
}

function Invoke-CapabilityAssessment {
    Write-ToolLog "Running Shadow Trace Ops capability assessment..." "INFO"

    Initialize-CapabilityMatrix

    try {
        if ($Script:Investigation.IdentityRisk.Count -gt 0 -and ($Script:Investigation.IdentityRisk -join ' ') -notmatch 'not collected|could not be completed|Graph is not connected') {
            Set-Capability -Name "EntraIdRisk" -Enabled $true
        }

        if ($Script:Investigation.Authentication.Count -gt 0 -and ($Script:Investigation.Authentication -join ' ') -notmatch 'not collected|could not be completed|Graph is not connected') {
            Set-Capability -Name "SignInLogs" -Enabled $true
        }

        if (($Script:Investigation.CollectionStatus["XdrAlerts"] -match "Completed") -or ($Script:Investigation.CollectionStatus["XdrIncidents"] -match "Completed")) {
            Set-Capability -Name "DefenderXdr" -Enabled $true
        }

        if (($Script:Investigation.CollectionStatus["EndpointContext"] -match "Completed") -and ($Script:Investigation.CollectionStatus["EndpointContext"] -notmatch "Skipped|Failed")) {
            Set-Capability -Name "DefenderForEndpoint" -Enabled $true
            Set-Capability -Name "AdvancedHunting" -Enabled $true
        }

        if (($Script:Investigation.CollectionStatus["EmailContext"] -match "Completed") -and ($Script:Investigation.CollectionStatus["EmailContext"] -notmatch "Skipped|Failed")) {
            Set-Capability -Name "DefenderForOffice365" -Enabled $true
            Set-Capability -Name "AdvancedHunting" -Enabled $true
        }

        if (($Script:Investigation.CollectionStatus["UrlClickContext"] -match "Completed") -and ($Script:Investigation.CollectionStatus["UrlClickContext"] -notmatch "Skipped|Failed")) {
            Set-Capability -Name "DefenderForOffice365" -Enabled $true
            Set-Capability -Name "AdvancedHunting" -Enabled $true
        }

        if (($Script:Investigation.CollectionStatus["CloudAppEvents"] -match "Completed") -and ($Script:Investigation.CollectionStatus["CloudAppEvents"] -notmatch "Skipped|Failed")) {
            Set-Capability -Name "DefenderForCloudApps" -Enabled $true
            Set-Capability -Name "AdvancedHunting" -Enabled $true
        }

        if ($Script:Investigation.OAuthActivity.Count -gt 0 -and ($Script:Investigation.OAuthActivity -join ' ') -notmatch 'not collected|could not be completed|Graph is not connected') {
            Set-Capability -Name "OAuthVisibility" -Enabled $true
        }

        if ($Script:Investigation.DlpVisibility.Count -gt 0) {
            Set-Capability -Name "DlpVisibility" -Enabled $true
        }

        $enabledCount = @($Script:Investigation.Capabilities.Values | Where-Object { $_ -eq $true }).Count

        if ($enabledCount -ge 8) {
            $Script:Investigation.ProductReadiness = "Phase 2 Ready"
        }
        elseif ($enabledCount -ge 5) {
            $Script:Investigation.ProductReadiness = "Partial Phase 2"
        }
        else {
            $Script:Investigation.ProductReadiness = "Phase 1 Advisory"
        }

        Add-UniqueInvestigationItem -Section "SourceHealth" -Value "Product readiness assessment: $($Script:Investigation.ProductReadiness)"

        foreach ($capability in $Script:Investigation.Capabilities.GetEnumerator()) {
            $status = if ($capability.Value) { "Available" } else { "Unavailable or not detected" }
            Add-UniqueInvestigationItem -Section "SourceHealth" -Value "$($capability.Key): $status"
        }

        Write-ToolLog "Capability assessment completed. Product readiness: $($Script:Investigation.ProductReadiness)" "SUCCESS"
    }
    catch {
        Write-ToolLog "Capability assessment failed: $($_.Exception.Message)" "WARN"
    }
}

function Test-RunModeSafety {
    param(
        [int]$LookbackDays,
        [string]$RunMode
    )

    if ($RunMode -eq "Executive Report" -and $LookbackDays -eq 90) {
        [System.Windows.Forms.MessageBox]::Show(
            "Executive Report mode with a 90-day lookback is intentionally blocked to prevent long-running Advanced Hunting queries. Use 30 days in Executive Report mode, or switch to Investigation mode for 90 days.",
            "Expanded Mode Safety Guard",
            "OK",
            "Warning"
        ) | Out-Null
        Write-ToolLog "Executive Report mode with 90-day lookback was blocked by the safety guard." "WARN"
        return $false
    }

    if ($RunMode -eq "Executive Report") {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Executive Report mode runs deeper Advanced Hunting queries and may take longer. Continue?",
            "Confirm Expanded Mode",
            "YesNo",
            "Warning"
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-ToolLog "Executive Report mode run was cancelled by the user." "WARN"
            return $false
        }
    }

    return $true
}

function Set-ScopeToggleStyle {
    param([System.Windows.Forms.CheckBox]$Toggle)

    if (-not $Toggle) { return }

    $Toggle.Appearance = [System.Windows.Forms.Appearance]::Normal
    $Toggle.AutoSize = $false
    $Toggle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $Toggle.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
    $Toggle.UseVisualStyleBackColor = $false
    $Toggle.BackColor = $Script:Theme.PanelBack
    $Toggle.ForeColor = $Script:Theme.TextFore
    $Toggle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $Toggle.Cursor = [System.Windows.Forms.Cursors]::Default
}

function New-ScopeToggleButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W = 245,
        [int]$H = 38
    )

    $toggle = New-Object System.Windows.Forms.CheckBox
    $toggle.Text = $Text
    $toggle.Checked = $true
    $toggle.Location = New-Object System.Drawing.Point($X, $Y)
    $toggle.Size = New-Object System.Drawing.Size($W, $H)
    Set-ScopeToggleStyle -Toggle $toggle
    return $toggle
}


function Test-CanExportShadowTraceReport {
    if (-not $Script:Investigation) {
        [System.Windows.Forms.MessageBox]::Show(
            "No successful investigation data exists yet. Run an investigation first.",
            "No Investigation Data",
            "OK",
            "Warning"
        ) | Out-Null
        return $false
    }

    $investigationUpn = $null
    try {
        if ($Script:Investigation.UserPrincipalName) {
            $investigationUpn = [string]$Script:Investigation.UserPrincipalName
        }
    }
    catch {}

    $resolutionStatus = $null
    try {
        if ($Script:Investigation.UserSummary -and $Script:Investigation.UserSummary.Contains("ResolutionStatus")) {
            $resolutionStatus = [string]$Script:Investigation.UserSummary["ResolutionStatus"]
        }
    }
    catch {}

    if ($resolutionStatus -match "Failed|Not resolved") {
        [System.Windows.Forms.MessageBox]::Show(
            "The current investigation contains an unresolved user state. Reports will not be generated.",
            "Target User Not Resolved",
            "OK",
            "Error"
        ) | Out-Null
        Write-ToolLog "Report export blocked because investigation UserSummary indicates unresolved user state." "ERROR"
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($investigationUpn) -and $investigationUpn -match '@') {
        if (-not $Script:TargetUserResolved) {
            $Script:TargetUserResolved = $true
            $Script:LastResolvedUserPrincipalName = $investigationUpn
            Write-ToolLog "Report export guard recovered valid user from successful investigation state: $investigationUpn" "INFO"
        }
        return $true
    }

    [System.Windows.Forms.MessageBox]::Show(
        "The current investigation does not contain a valid resolved user. Reports will not be generated.",
        "Target User Not Resolved",
        "OK",
        "Error"
    ) | Out-Null
    Write-ToolLog "Report export blocked because investigation state does not contain a valid resolved user." "ERROR"
    return $false
}

function Stop-UnresolvedTargetUser {
    

    $Script:TargetUserResolved = $false
    $Script:LastResolvedUserPrincipalName = $null
    $Script:Investigation = $null

    Set-CollectionStatus -Name "UserResolution" -Status "Failed"

    $message = "USER_RESOLUTION_FAILED: Target user could not be resolved: $UserPrincipalName. $Reason"
    Write-ToolLog $message "ERROR"

    [System.Windows.Forms.MessageBox]::Show(
        "Target user could not be resolved:`r`n$UserPrincipalName`r`n`r`n$Reason`r`n`r`nInvestigation stopped. No report was generated.",
        "User Resolution Failed",
        "OK",
        "Error"
    ) | Out-Null

    throw $message
}



function Resolve-TargetUser {
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserPrincipalName
    )

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        Stop-UnresolvedTargetUser -UserPrincipalName "<blank>" -Reason "A user principal name is required."
    }

    $Script:TargetUserResolved = $false
    $Script:LastResolvedUserPrincipalName = $null

    Set-CollectionStatus -Name "UserResolution" -Status "Running"
    Write-ToolLog "Resolving target user: $UserPrincipalName" "INFO"

    try {
        $resolvedUser = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop

        if ($null -eq $resolvedUser) {
            Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason "Microsoft Graph returned no user object."
        }

        if ([string]::IsNullOrWhiteSpace($resolvedUser.Id) -or [string]::IsNullOrWhiteSpace($resolvedUser.UserPrincipalName)) {
            Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason "Microsoft Graph returned an incomplete user object."
        }

        $Script:TargetUserResolved = $true
        $Script:LastResolvedUserPrincipalName = $resolvedUser.UserPrincipalName

        Set-CollectionStatus -Name "UserResolution" -Status "Completed"
        Write-ToolLog "Resolved target user: $($resolvedUser.UserPrincipalName)" "SUCCESS"

        return $resolvedUser
    }
    catch {
        if ($_.Exception.Message -match "USER_RESOLUTION_FAILED") {
            throw
        }

        Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason $_.Exception.Message
    }
}

function Start-PostAuthInvestigation {
    $Script:TargetUserResolved = $false
    $Script:LastResolvedUserPrincipalName = $null

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

    $lookbackDays = [int]$Script:cmbAuthLookback.SelectedItem.ToString().Replace(" days", "")
    $runMode = $Script:cmbRunMode.SelectedItem.ToString()
    if (-not (Test-RunModeSafety -LookbackDays $lookbackDays -RunMode $runMode)) {
        return
    }

    $Script:Investigation.AuthLookbackDays = $lookbackDays
    $Script:Investigation.RunMode = $runMode

    if ($false) {
        $Script:Investigation.MaxQueryRows = 50
        $Script:Investigation.HuntingLookbackDays = $lookbackDays
        $Script:Investigation.IsSummaryOnlyRun = $false

        if ($lookbackDays -eq 7) {
            $Script:Investigation.InvestigationProfile = "Investigation 7d - Investigation"
        }
        elseif ($lookbackDays -eq 30) {
            $Script:Investigation.InvestigationProfile = "Investigation 30d - Targeted hunt"
        }
    }
    else {
        $Script:Investigation.MaxQueryRows = 10
        $Script:Investigation.HuntingLookbackDays = [Math]::Min($lookbackDays, 3)

        if ($lookbackDays -eq 90) {
            $Script:Investigation.IsSummaryOnlyRun = $true
            $Script:Investigation.InvestigationProfile = "Investigation 90d - Historical summary only"
        }
        elseif ($lookbackDays -eq 30) {
            $Script:Investigation.IsSummaryOnlyRun = $false
            $Script:Investigation.InvestigationProfile = "Investigation 30d - Broader trend review"
        }
        else {
            $Script:Investigation.IsSummaryOnlyRun = $false
            $Script:Investigation.InvestigationProfile = "Investigation 7d - Normal investigation"
        }
    }

    Write-ToolLog "Starting Phase 1 post-authentication investigation for $UserPrincipalName" "INFO"
    Write-ToolLog "Authentication log drill-down selected: $lookbackDays day(s)." "INFO"
    Write-ToolLog "Run mode selected: $runMode. Profile=$($Script:Investigation.InvestigationProfile). MaxQueryRows=$($Script:Investigation.MaxQueryRows). HuntingLookbackDays=$($Script:Investigation.HuntingLookbackDays). SummaryOnly=$($Script:Investigation.IsSummaryOnlyRun)." "INFO"
    Write-ToolLog "Workflow: identity risk -> authentication -> cloud activity -> session behavior -> findings -> potential gaps -> recommendations" "INFO"

    try {
        $isConnected = Get-GraphConnectionStatus
        if (-not $isConnected) {
            Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason "Microsoft Graph is not connected. Use Connect Services before running the investigation."
        }

        $resolvedUser = Resolve-InvestigationUser -UserPrincipalName $UserPrincipalName

        if ($null -eq $resolvedUser -or [string]::IsNullOrWhiteSpace($resolvedUser.Id) -or [string]::IsNullOrWhiteSpace($resolvedUser.UserPrincipalName)) {
            Stop-UnresolvedTargetUser -UserPrincipalName $UserPrincipalName -Reason "User resolution did not produce a valid Microsoft Graph user object."
        }

        $Script:TargetUserResolved = $true
        $Script:LastResolvedUserPrincipalName = $resolvedUser.UserPrincipalName
        $UserPrincipalName = $resolvedUser.UserPrincipalName

        if ($Script:chkIdentity.Checked -and $isConnected) {
            Get-IdentityRiskPhase1 -UserId $resolvedUser.Id -UserPrincipalName $UserPrincipalName
        }
        elseif ($Script:chkIdentity.Checked) {
            $Script:Investigation.IdentityRisk += "Graph is not connected. Identity risk data was not collected in this run."
        }

        if ($Script:chkAuthentication.Checked -and $isConnected) {
            Get-SignInActivityPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $lookbackDays
        }
        elseif ($Script:chkAuthentication.Checked) {
            $Script:Investigation.Authentication += "Graph is not connected. Sign-in activity was not collected in this run."
        }

        if ($Script:chkOAuth.Checked -and $isConnected -and $resolvedUser) {
            Get-OAuthAppActivityPhase1 -UserId $resolvedUser.Id -UserPrincipalName $UserPrincipalName
        }
        elseif ($Script:chkOAuth.Checked -and -not $isConnected) {
            Add-UniqueInvestigationItem -Section "OAuthActivity" -Value "Graph is not connected. OAuth and application activity was not collected in this run."
        }

        if ($Script:chkAlerts.Checked -and $isConnected) {
            Get-XdrAlertContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $lookbackDays
            Get-XdrIncidentContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $lookbackDays
        }
        elseif ($Script:chkAlerts.Checked -and -not $isConnected) {
            Add-UniqueInvestigationItem -Section "Alerts" -Value "Graph is not connected. Defender XDR alert context was not collected in this run."
        }

        Add-Phase1CloudAndGapPlaceholders
        if (-not $Script:Investigation.IsSummaryOnlyRun) {
            Get-EndpointContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $Script:Investigation.HuntingLookbackDays
        }
        else {
            Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint Advanced Hunting skipped because this is a Standard 90-day historical summary run. Use Expanded 7/30 days for deep endpoint investigation."
            Set-CollectionStatus -Name "EndpointContext" -Status "Skipped - 90d summary mode"
        }
        if (-not $Script:Investigation.IsSummaryOnlyRun) {
            Get-EmailPhishingContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $Script:Investigation.HuntingLookbackDays
        }
        else {
            Add-UniqueInvestigationItem -Section "EmailContext" -Value "Email Advanced Hunting skipped because this is a Standard 90-day historical summary run. Review identity, authentication, OAuth, and XDR summaries first, then run Expanded 7/30 days around suspicious windows."
            Set-CollectionStatus -Name "EmailContext" -Status "Skipped - 90d summary mode"
        }
        if ($runMode -eq "Executive Report" -and -not $Script:Investigation.IsSummaryOnlyRun) {
            Get-UrlClickContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $Script:Investigation.HuntingLookbackDays
        }
        else {
            Add-UniqueInvestigationItem -Section "UrlClickContext" -Value "URL click context skipped in Investigation mode. Use Executive Report mode for deeper URL click hunting."
            Set-CollectionStatus -Name "UrlClickContext" -Status "Skipped - Investigation mode"
        }
        if ($runMode -eq "Executive Report" -and -not $Script:Investigation.IsSummaryOnlyRun) {
            Get-CloudAppEventsContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $Script:Investigation.HuntingLookbackDays
        }
        else {
            Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "CloudAppEvents hunting skipped in Investigation mode. Use Executive Report mode for deeper Defender for Cloud Apps activity hunting."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Skipped - Investigation mode"
        }
        Invoke-CloudSessionGapAssessmentPhase1
        Invoke-CapabilityAssessment
        Invoke-Phase1AssessmentLogic
        Build-UnifiedTimelinePhase1
        Add-Phase1ReadOnlyReminder

        $Script:Investigation.EndTime = Get-Date

        Write-ToolLog "Phase 1 investigation workflow completed for $UserPrincipalName." "SUCCESS"
        Write-ToolLog "Use Export HTML Report to generate the investigation report." "INFO"
    }
    catch {
        if ($_.Exception.Message -match "USER_RESOLUTION_FAILED") {
            $Script:Investigation = $null
            Write-ToolLog "User resolution failed; investigation stopped before collectors." "ERROR"
            return
        }
        Write-ToolLog "Investigation failed: $($_.Exception.Message)" "ERROR"
    }
}

# ------------------------------------------------------------
# Report Functions
# ------------------------------------------------------------
function Export-DetailedWorkflowReport {
    
    param([string]$SummaryReportPath)

    
    if (-not (Test-CanExportShadowTraceReport)) { return $null }
if (-not $Script:Investigation) { return $null }

    try {
        $upn = $Script:Investigation.UserPrincipalName
        $safeName = $upn.Replace("@", "_").Replace(".", "_").Replace("\", "_").Replace("/", "_")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $detailFile = Join-Path $Script:ReportPath "ShadowTraceOps-DetailedWorkflow-$safeName-$timestamp.html"

        $logoHtml = Get-LogoHtml
        $tenantLogoHtml = Get-TenantLogoHtml
        $userSummaryTable = ConvertTo-HtmlTableFromHashtable $Script:Investigation.UserSummary
        Save-AnalystWorkflowToInvestigation
        $analystWorkflowHtml = Convert-AnalystWorkflowToHtml
        $analystTimelineHtml = Convert-AnalystTimelineToHtml
        $potentialRemediationHtml = Convert-PotentialRemediationToHtml
        $workflowMaturityHtml = Convert-InvestigationWorkflowMaturityToHtml
        $dispositionHtml = Convert-InvestigationDispositionToHtml
        $perSectionNotesHtml = Convert-PerSectionAnalystNotesToHtml
        $timelineCorrelationHtml = Convert-InvestigationTimelineCorrelationToHtml
        $gapClosureHtml = Convert-GapClosureGuidanceToHtml
        $kqlValidationHtml = Convert-KqlExecutionValidationToHtml
        $authCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Authentication -PreviewCount 200 -EmptyMessage "No authentication records were collected."
        $identityCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.IdentityRisk -PreviewCount 200 -EmptyMessage "No identity risk details were collected."
        $oauthCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.OAuthActivity -PreviewCount 200 -EmptyMessage "No OAuth details were collected."
        $xdrCards = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.Alerts + $Script:Investigation.Incidents) -PreviewCount 200 -EmptyMessage "No XDR details were collected."
        $endpointCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.EndpointContext -PreviewCount 200 -EmptyMessage "No endpoint details were collected."
        $emailCards = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.EmailContext + $Script:Investigation.UrlClickContext) -PreviewCount 200 -EmptyMessage "No email or URL click details were collected."
        $cloudCards = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.CloudActivity + $Script:Investigation.CloudAppEvents) -PreviewCount 200 -EmptyMessage "No cloud app details were collected."
        $gapCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.PotentialGaps -PreviewCount 200 -EmptyMessage "No potential gaps were identified."
        $recommendationCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Recommendations -PreviewCount 200 -EmptyMessage "No recommendations were generated."
        $sourceHealthCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.SourceHealth -PreviewCount 200 -EmptyMessage "No source health diagnostics were captured."

        $html = @"
<!DOCTYPE html>
<html>
<head>
<title>Shadow Trace Ops Detailed Workflow Report</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; background: #09090f; color: #eeeeff; margin: 0; padding: 28px; }
.shell { max-width: 1400px; margin: 0 auto; }
.header { border: 1px solid #503e62; border-left: 6px solid #b784ff; border-radius: 18px; padding: 26px; background: linear-gradient(135deg, #1c1c24, #090912); box-shadow: 0 0 28px rgba(183,132,255,.20); }
.header-row { display: flex; justify-content: space-between; gap: 24px; align-items: flex-start; }
h1 { margin: 0; font-size: 38px; color: #fff; }
.ops { color: #b784ff; }
.subtitle { color: #cfc7dc; margin-top: 8px; }
.logo-stack { display: flex; gap: 16px; align-items: center; }
.tool-logo { max-width: 110px; max-height: 110px; border-radius: 16px; filter: drop-shadow(0 0 18px rgba(183,132,255,.45)); }
.tenant-logo { max-width: 120px; max-height: 80px; object-fit: contain; border: 1px solid #503e62; border-radius: 12px; padding: 10px; background: rgba(255,255,255,.05); }
.tenant-logo-placeholder { width: 120px; height: 80px; display: flex; align-items: center; justify-content: center; text-align: center; color: #8f86a3; border: 1px dashed #503e62; border-radius: 12px; font-size: 12px; }
.meta { display: grid; grid-template-columns: repeat(2, minmax(250px, 1fr)); gap: 8px 20px; margin-top: 18px; color: #d6d6de; }
.meta span { color: #b784ff; font-weight: 700; }
.section { margin-top: 20px; border: 1px solid #3f3150; border-left: 5px solid #b784ff; border-radius: 14px; padding: 18px; background: rgba(28,28,36,.96); }
h2 { color: #caa2ff; margin-top: 0; }
h3 { color: #ffffff; margin-bottom: 8px; }
.workflow { display: grid; grid-template-columns: repeat(6, 1fr); gap: 10px; margin-top: 14px; }
.step { border: 1px solid #503e62; border-radius: 12px; background: #15151d; padding: 14px; text-align: center; color: #fff; }
.step .num { color: #b784ff; font-size: 22px; font-weight: 800; }
.report-card { background: #12121a; border: 1px solid #342643; border-radius: 10px; padding: 12px 14px; margin-bottom: 10px; line-height: 1.45; }
.muted-card { color: #b8b2c4; }
table { border-collapse: collapse; width: 100%; margin-top: 8px; }
th { text-align: left; width: 260px; background: #24242e; color: #caa2ff; border: 1px solid #503e62; padding: 9px; }
td { border: 1px solid #503e62; padding: 9px; color: #ebebf0; }
.callout { border: 1px solid #6b4e8a; background: #171020; padding: 14px; border-radius: 12px; color: #e8ddff; }
.footer { margin-top: 24px; color: #aaa; border-top: 1px solid #3f3150; padding-top: 16px; display: flex; justify-content: space-between; }
</style>
</head>
<body>
<div class='shell'>
  <div class='header'>
    <div class='header-row'>
      <div>
        <h1>SHADOW TRACE <span class='ops'>OPS</span> DETAILED WORKFLOW</h1>
        <div class='subtitle'>Step-by-step post-authentication investigation and pivot guide</div>
      </div>
      <div class='logo-stack'>$tenantLogoHtml $logoHtml</div>
    </div>
    <div class='meta'>
      <div><span>Generated:</span> $(Get-Date)</div>
      <div><span>Investigator:</span> $env:USERNAME</div>
      <div><span>Target User:</span> $upn</div>
      <div><span>Lookback:</span> $($Script:Investigation.AuthLookbackDays) day(s)</div>
      <div><span>Run Mode:</span> $($Script:Investigation.RunMode)</div>
      <div><span>Profile:</span> $($Script:Investigation.InvestigationProfile)</div>
      <div><span>Readiness:</span> $($Script:Investigation.ProductReadiness)</div>
      <div><span>Priority:</span> $($Script:Investigation.Priority)</div>
      <div><span>Run ID:</span> $($Script:Investigation.RunId)</div>
    </div>
  </div>

  <div class='section'>
    <h2>Investigation Workflow</h2>
    <div class='workflow'>
      <div class='step'><div class='num'>1</div>Confirm identity risk</div>
      <div class='step'><div class='num'>2</div>Review authentication</div>
      <div class='step'><div class='num'>3</div>Check email and URL path</div>
      <div class='step'><div class='num'>4</div>Correlate endpoint/XDR</div>
      <div class='step'><div class='num'>5</div>Review cloud/session activity</div>
      <div class='step'><div class='num'>6</div>Document gaps and pivots</div>
    </div>
  </div>

  <div class='section'><h2>User Summary</h2>$userSummaryTable</div>
  <div class='section'><h2>Step 1 — Identity Risk Review</h2><div class='callout'>Determine whether Entra ID risk data changes the trust level of the authenticated session.</div>$identityCards</div>
  <div class='section'><h2>Step 2 — Authentication Drilldown</h2><div class='callout'>Review sign-in success/failure, app, IP, location, device trust, Conditional Access result, and sign-in risk fields.</div>$authCards</div>
  <div class='section'><h2>Step 3 — Email and URL Click Path</h2><div class='callout'>Look for phishing delivery, Safe Links clicks, suspicious email activity, and timing before successful authentication.</div>$emailCards</div>
  <div class='section'><h2>Step 4 — Endpoint and XDR Correlation</h2><div class='callout'>Correlate user, device, alert, incident, and Advanced Hunting evidence around the same timeframe.</div>$endpointCards $xdrCards</div>
  <div class='section'><h2>Step 5 — OAuth and Application Activity</h2><div class='callout'>Review delegated grants, high-interest scopes, consent timing, and governance coverage.</div>$oauthCards</div>
  <div class='section'><h2>Step 6 — Cloud Activity and Session Behavior</h2><div class='callout'>Review cloud actions, app usage, unmanaged device access, session controls, and data movement indicators.</div>$cloudCards</div>
  <div class='section'><h2>Step 7 — Potential Defensive Gaps</h2>$gapCards</div>
  <div class='section'><h2>Step 8 — Suggested Defensive Improvements</h2>$recommendationCards</div>
  <div class='section'><h2>Source Health Diagnostics</h2>$sourceHealthCards</div>

  <div class='footer'><span>Shadow Trace Ops · Detailed Workflow</span><span>Read-only advisory report</span></div>
</div>


<script>
function htmlEscape(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildAnalystSummaryHtml() {
  var assessmentEl = document.getElementById('analystAssessment');
  var notesEl = document.getElementById('analystNotes');

  var assessment = assessmentEl ? assessmentEl.value : '';
  var notes = notesEl ? notesEl.value : '';

  var checks = Array.prototype.slice.call(document.querySelectorAll('[data-workflow]'));
  var selected = checks.filter(function(cb) { return cb.checked; }).map(function(cb) {
    return '<li>' + htmlEscape(cb.getAttribute('data-workflow')) + '</li>';
  }).join('');

  if (!selected) {
    selected = '<li>No workflow status selections were checked.</li>';
  }

  return '<h3>Embedded Analyst Summary</h3>' +
    '<h4>Analyst Assessment</h4><p>' + htmlEscape(assessment || 'No analyst assessment entered.') + '</p>' +
    '<h4>Analyst Notes</h4><p>' + htmlEscape(notes || 'No analyst notes entered.') + '</p>' +
    '<h4>Workflow Status</h4><ul>' + selected + '</ul>' +
    '<p><em id="analystUpdatedStamp">Updated in-report on ' + htmlEscape(new Date().toLocaleString()) + '.</em></p>';
}

function syncAnalystSummary(targetDoc) {
  var doc = targetDoc || document;
  var summary = doc.getElementById('embeddedAnalystSummary');

  if (summary && doc === document) {
    summary.innerHTML = buildAnalystSummaryHtml();
  }

  var assessment = doc.getElementById('analystAssessment');
  var notes = doc.getElementById('analystNotes');

  if (assessment) {
    assessment.textContent = assessment.value || assessment.textContent || '';
    assessment.setAttribute('data-saved-value', assessment.value || assessment.textContent || '');
  }

  if (notes) {
    notes.textContent = notes.value || notes.textContent || '';
    notes.setAttribute('data-saved-value', notes.value || notes.textContent || '');
  }

  var checks = Array.prototype.slice.call(doc.querySelectorAll('[data-workflow]'));
  checks.forEach(function(cb) {
    if (cb.checked) {
      cb.setAttribute('checked', 'checked');
    } else {
      cb.removeAttribute('checked');
    }
  });
}

function getSafeReportFileName() {
  var title = document.title || 'ShadowTraceOps-PrimaryDashboard';
  title = title.replace(/[^a-zA-Z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');
  if (!title) { title = 'ShadowTraceOps-PrimaryDashboard'; }
  return title + '-UPDATED.html';
}

function buildUpdatedReportHtml() {
  syncAnalystSummary();

  var clone = document.documentElement.cloneNode(true);

  var clonedAssessment = clone.querySelector('#analystAssessment');
  var clonedNotes = clone.querySelector('#analystNotes');
  var sourceAssessment = document.getElementById('analystAssessment');
  var sourceNotes = document.getElementById('analystNotes');

  if (clonedAssessment && sourceAssessment) {
    clonedAssessment.textContent = sourceAssessment.value || '';
    clonedAssessment.setAttribute('data-saved-value', sourceAssessment.value || '');
  }

  if (clonedNotes && sourceNotes) {
    clonedNotes.textContent = sourceNotes.value || '';
    clonedNotes.setAttribute('data-saved-value', sourceNotes.value || '');
  }

  var clonedSummary = clone.querySelector('#embeddedAnalystSummary');
  if (clonedSummary) {
    clonedSummary.innerHTML = buildAnalystSummaryHtml();
  }

  var sourceChecks = Array.prototype.slice.call(document.querySelectorAll('[data-workflow]'));
  var clonedChecks = Array.prototype.slice.call(clone.querySelectorAll('[data-workflow]'));

  sourceChecks.forEach(function(sourceCb, i) {
    var clonedCb = clonedChecks[i];
    if (!clonedCb) { return; }
    if (sourceCb.checked) {
      clonedCb.setAttribute('checked', 'checked');
    } else {
      clonedCb.removeAttribute('checked');
    }
  });

  var sourceRemediation = Array.prototype.slice.call(document.querySelectorAll('[data-remediation-status]'));
  var clonedRemediation = Array.prototype.slice.call(clone.querySelectorAll('[data-remediation-status]'));
  sourceRemediation.forEach(function(sourceSelect, i) {
    var clonedSelect = clonedRemediation[i];
    if (!clonedSelect) { return; }
    Array.prototype.slice.call(clonedSelect.options).forEach(function(option) {
      if (option.text === sourceSelect.value) {
        option.setAttribute('selected', 'selected');
      } else {
        option.removeAttribute('selected');
      }
    });
  });

  return '<!DOCTYPE html>\n' + clone.outerHTML;
}

function showSaveStatus(message, isError) {
  var status = document.getElementById('reportSaveStatus');
  if (!status) {
    status = document.createElement('div');
    status.id = 'reportSaveStatus';
    status.className = 'report-save-status';
    var panel = document.querySelector('.analyst-live-panel');
    if (panel) {
      panel.insertBefore(status, panel.firstChild);
    } else {
      document.body.insertBefore(status, document.body.firstChild);
    }
  }

  status.textContent = message;
  status.style.display = 'block';
  status.style.borderColor = isError ? '#ff8d8d' : '#6ee7a0';
  status.style.color = isError ? '#ff8d8d' : '#6ee7a0';
}

function generateAnalystSummary() {
  try {
    var html = buildUpdatedReportHtml();
    var filename = getSafeReportFileName();

    var blob = new Blob([html], { type: 'text/html;charset=utf-8' });
    var url = URL.createObjectURL(blob);

    var a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.style.display = 'none';

    document.body.appendChild(a);
    a.click();

    setTimeout(function() {
      URL.revokeObjectURL(url);
      if (a.parentNode) { a.parentNode.removeChild(a); }
    }, 1000);

    showSaveStatus('Updated report download started. Check your browser Downloads folder. The file name is: ' + filename + '. If a previous UPDATED file exists, replace it when prompted.', false);
  }
  catch (err) {
    showSaveStatus('Download failed in this browser context. The embedded summary has still been updated in the page. Use Ctrl+S to save the report manually, or open the report in Edge/Chrome and try again. Error: ' + err.message, true);
  }
}

document.addEventListener('input', function(e) {
  if (e.target && (e.target.id === 'analystAssessment' || e.target.id === 'analystNotes')) {
    syncAnalystSummary();
  }
});

document.addEventListener('change', function(e) {
  if (e.target && e.target.hasAttribute('data-workflow')) {
    syncAnalystSummary();
  }
});

document.addEventListener('DOMContentLoaded', function() {
  var assessment = document.getElementById('analystAssessment');
  var notes = document.getElementById('analystNotes');

  if (assessment && assessment.getAttribute('data-saved-value')) {
    assessment.value = assessment.getAttribute('data-saved-value');
  }

  if (notes && notes.getAttribute('data-saved-value')) {
    notes.value = notes.getAttribute('data-saved-value');
  }

  syncAnalystSummary();
});
</script>


</body>
</html>
"@

        $html | Out-File -FilePath $detailFile -Encoding UTF8
        Test-ShadowTraceHtmlReportFile -Path $detailFile -ReportName "Detailed workflow report" | Out-Null
        Write-ToolLog "Detailed workflow report exported: $detailFile" "SUCCESS"
        return $detailFile
    }
    catch {
        Write-ToolLog "Detailed workflow report export failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}

function Add-Phase1ReadOnlyReminder {
    Add-UniqueInvestigationItem -Section "Recommendations" -Value "Shadow Trace Ops is currently operating in a read-only advisory mode. The toolkit does not perform automatic remediation, session revocation, account disablement, or enforcement actions."

    Add-UniqueInvestigationItem -Section "Recommendations" -Value "Investigation findings should be reviewed by analysts and validated against organizational processes, telemetry quality, licensing coverage, and operational response procedures."
}


function Get-ExecutiveCount {
    param([string]$Name)

    switch ($Name) {
        "Authentication" { if ($Script:Investigation.Authentication) { return $Script:Investigation.Authentication.Count } else { return 0 } }
        "IdentityRisk" { if ($Script:Investigation.IdentityRisk) { return $Script:Investigation.IdentityRisk.Count } else { return 0 } }
        "Cloud" { return @($Script:Investigation.CloudActivity + $Script:Investigation.CloudAppEvents).Count }
        "Xdr" { return @($Script:Investigation.Alerts + $Script:Investigation.Incidents).Count }
        "Source" { if ($Script:Investigation.SourceHealth) { return $Script:Investigation.SourceHealth.Count } else { return 0 } }
        "Url" { return @($Script:Investigation.EmailContext + $Script:Investigation.UrlClickContext).Count }
        default { return 0 }
    }
}

function Convert-ExecutiveFindingsToHtml {
    $items = @($Script:Investigation.ObservedRisks + $Script:Investigation.PotentialGaps + $Script:Investigation.InvestigationPivots + $Script:Investigation.Recommendations) | Select-Object -First 6

    if (-not $items -or $items.Count -eq 0) {
        $items = @(
            "No elevated findings were generated by this run.",
            "Review the detailed workflow report for source health, no-result collectors, and telemetry availability.",
            "Use the dashboard report for priority areas and investigation pivots."
        )
    }

    $htmlItems = foreach ($item in $items) {
        "<li>$(ConvertTo-SafeHtml $item)</li>"
    }

    return "<ul class='finding-list'>$($htmlItems -join "`n")</ul>"
}

function Convert-ExecutiveReadinessToHtml {
    $rows = @()

    if ($Script:Investigation.Capabilities) {
        foreach ($capability in $Script:Investigation.Capabilities.GetEnumerator()) {
            $status = if ($capability.Value) { "<span class='available'>Available</span>" } else { "<span class='limited'>Unavailable / Not detected</span>" }
            $rows += "<tr><td>$(ConvertTo-SafeHtml $capability.Key)</td><td>$status</td></tr>"
        }
    }

    if ($rows.Count -eq 0) {
        $rows += "<tr><td>Microsoft Graph / Defender telemetry</td><td><span class='limited'>Not assessed</span></td></tr>"
    }

    return "<table class='readiness-table'><tr><th>Data Source</th><th>Status</th></tr>$($rows -join "`n")</table>"
}

function Convert-ExecutiveNotableTableToHtml {
    $items = @($Script:Investigation.Authentication + $Script:Investigation.OAuthActivity + $Script:Investigation.CloudAppEvents + $Script:Investigation.Alerts + $Script:Investigation.Incidents + $Script:Investigation.UrlClickContext) | Select-Object -First 5
    $rows = @()

    foreach ($item in $items) {
        $rows += "<tr><td>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</td><td>$(ConvertTo-SafeHtml $Script:Investigation.UserPrincipalName)</td><td>$(ConvertTo-SafeHtml $item)</td><td>Shadow Trace Ops</td><td>Review</td></tr>"
    }

    if ($rows.Count -eq 0) {
        $rows += "<tr><td colspan='5'>No notable event rows were available. See the dashboard and detailed workflow reports for source health and no-result collectors.</td></tr>"
    }

    return @"
<table class='table-clean'>
<tr><th>Time</th><th>User</th><th>Activity</th><th>Workload</th><th>Result</th></tr>
$($rows -join "`n")
</table>
"@
}


function Get-ExecutiveReportMetricCounts {
    $authCount = 0; $riskCount = 0; $cloudCount = 0; $xdrCount = 0; $urlCount = 0; $oauthCount = 0; $gapCount = 0
    try { if ($Script:Investigation.Authentication) { $authCount = @($Script:Investigation.Authentication).Count } } catch {}
    try { if ($Script:Investigation.IdentityRisk) { $riskCount = @($Script:Investigation.IdentityRisk).Count } } catch {}
    try { if ($Script:Investigation.CloudActivity) { $cloudCount += @($Script:Investigation.CloudActivity).Count } } catch {}
    try { if ($Script:Investigation.CloudAppEvents) { $cloudCount += @($Script:Investigation.CloudAppEvents).Count } } catch {}
    try { if ($Script:Investigation.OAuthActivity) { $oauthCount += @($Script:Investigation.OAuthActivity).Count } } catch {}
    try { if ($Script:Investigation.Alerts) { $xdrCount += @($Script:Investigation.Alerts).Count } } catch {}
    try { if ($Script:Investigation.Incidents) { $xdrCount += @($Script:Investigation.Incidents).Count } } catch {}
    try { if ($Script:Investigation.EndpointContext) { $xdrCount += @($Script:Investigation.EndpointContext).Count } } catch {}
    try { if ($Script:Investigation.EmailContext) { $urlCount += @($Script:Investigation.EmailContext).Count } } catch {}
    try { if ($Script:Investigation.UrlClickContext) { $urlCount += @($Script:Investigation.UrlClickContext).Count } } catch {}
    try { if ($Script:Investigation.PotentialGaps) { $gapCount = @($Script:Investigation.PotentialGaps).Count } } catch {}
    $coverageAreas = 0
    foreach ($value in @($authCount,$riskCount,$cloudCount,$xdrCount,$urlCount,$oauthCount)) { if ($value -gt 0) { $coverageAreas++ } }
    $coveragePct = [math]::Round(($coverageAreas / 6) * 100, 0)
    $total = $authCount + $riskCount + $cloudCount + $xdrCount + $urlCount + $oauthCount + $gapCount
    return [ordered]@{ Authentication=$authCount; IdentityRisk=$riskCount; Cloud=$cloudCount; EndpointXdr=$xdrCount; EmailUrl=$urlCount; OAuth=$oauthCount; Gaps=$gapCount; CoveragePct=$coveragePct; Total=$total }
}

function Get-ExecutivePriorityModel {
    param([hashtable]$Counts)
    $score = 0; $reasons = @()
    if ($Counts.IdentityRisk -gt 0) { $score += 20; $reasons += 'Identity risk or risky-user context is present.' }
    if ($Counts.Authentication -gt 0) { $score += 10; $reasons += 'Authentication data is available for review.' }
    if ($Counts.EndpointXdr -gt 0) { $score += 20; $reasons += 'Endpoint/XDR evidence or context is present.' }
    if ($Counts.EmailUrl -gt 0) { $score += 10; $reasons += 'Email or URL context is present.' }
    if ($Counts.Cloud -gt 0) { $score += 10; $reasons += 'Cloud activity context is present.' }
    if ($Counts.OAuth -gt 0) { $score += 10; $reasons += 'OAuth/application access context is present.' }
    if ($Counts.Gaps -gt 0) { $score += 20; $reasons += 'Potential defensive gaps were identified.' }
    if ($score -gt 100) { $score = 100 }
    $classification = 'Low'; $priority = 'Routine Review'; $confidence = 'Needs Validation'
    if ($score -ge 75) { $classification = 'Critical'; $priority = 'Immediate Executive Review' }
    elseif ($score -ge 55) { $classification = 'High'; $priority = 'Prompt Executive Review' }
    elseif ($score -ge 30) { $classification = 'Medium'; $priority = 'Analyst Review Recommended' }
    if ($Counts.CoveragePct -ge 67) { $confidence = 'Moderate' }
    if ($Counts.CoveragePct -ge 84) { $confidence = 'Higher' }
    return [ordered]@{ Score=$score; Classification=$classification; Priority=$priority; Confidence=$confidence; Reasons=$reasons }
}

function Convert-ExecutiveExposureBarsToHtml {
    param([hashtable]$Counts)
    $values = @($Counts.Authentication,$Counts.IdentityRisk,$Counts.EmailUrl,$Counts.EndpointXdr,$Counts.OAuth,$Counts.Cloud,$Counts.Gaps)
    $maxMetric = ($values | Measure-Object -Maximum).Maximum
    if (-not $maxMetric -or $maxMetric -lt 1) { $maxMetric = 1 }
    $areas = @(
        @('Authentication',$Counts.Authentication,'Sign-in and access context'),
        @('Identity Risk',$Counts.IdentityRisk,'Risky user/sign-in context'),
        @('Email / URL',$Counts.EmailUrl,'Phishing delivery or URL interaction context'),
        @('Endpoint / XDR',$Counts.EndpointXdr,'Endpoint, alert, incident, or XDR context'),
        @('OAuth / Apps',$Counts.OAuth,'App consent and delegated permission context'),
        @('Cloud Activity',$Counts.Cloud,'Cloud/session/data activity context'),
        @('Defensive Gaps',$Counts.Gaps,'Control, coverage, or response gaps')
    )
    $rows = @()
    foreach ($area in $areas) {
        $label = [string]$area[0]; $value = [int]$area[1]; $desc = [string]$area[2]
        $pct = [math]::Round(($value / $maxMetric) * 100,0)
        $rows += "<div class='bar-row'><div class='bar-label'>$(ConvertTo-SafeHtml $label)</div><div class='bar-track'><span style='width:$pct%'></span></div><div class='bar-num'>$value</div><div class='bar-desc'>$(ConvertTo-SafeHtml $desc)</div></div>"
    }
    return ($rows -join "`n")
}

function Convert-ExecutivePriorityTimelineToHtml {
    $items = @(
        [ordered]@{When='0-24 Hours'; Title='Validate exposure and ownership'; Risk='High'; Difficulty='Low'; Dependencies='SOC analyst, Defender/Entra access'; Action='Confirm whether observed signals represent active risk, test activity, or expected behavior. Assign an accountable owner.'},
        [ordered]@{When='1-3 Days'; Title='Close critical visibility gaps'; Risk='High'; Difficulty='Medium'; Dependencies='Graph permissions, Defender roles, Advanced Hunting tables'; Action='Address missing telemetry, unavailable collectors, source health failures, and unknown sign-in or endpoint visibility gaps.'},
        [ordered]@{When='3-7 Days'; Title='Prioritize identity and session controls'; Risk='Medium'; Difficulty='Medium'; Dependencies='Conditional Access, session control, risk policies'; Action='Review risky-user controls, unmanaged device restrictions, MFA/CA behavior, and Conditional Access App Control coverage.'},
        [ordered]@{When='7-14 Days'; Title='Operationalize playbooks'; Risk='Medium'; Difficulty='Low'; Dependencies='SOC SOPs, KQL validation, response owners'; Action='Turn recurring pivots into standard operating procedures and validate KQL with known-good test cases.'},
        [ordered]@{When='30 Days'; Title='Measure improvement'; Risk='Low'; Difficulty='Medium'; Dependencies='Recurring executive review, baseline reports'; Action='Track reduced gaps, improved telemetry coverage, and faster analyst triage outcomes over time.'}
    )
    $html = @()
    foreach ($item in $items) {
        $html += "<div class='timeline-item'><div class='timeline-date'>$($item.When)</div><div class='timeline-card'><h3>$(ConvertTo-SafeHtml $item.Title)</h3><div><span>Risk: $(ConvertTo-SafeHtml $item.Risk)</span><span>Difficulty: $(ConvertTo-SafeHtml $item.Difficulty)</span></div><p>$(ConvertTo-SafeHtml $item.Action)</p><small>Dependencies: $(ConvertTo-SafeHtml $item.Dependencies)</small></div></div>"
    }
    return ($html -join "`n")
}

function Convert-ExecutiveGapCardsToHtml {
    $gaps = @()
    try { $gaps = @($Script:Investigation.PotentialGaps) } catch {}
    if (-not $gaps -or $gaps.Count -eq 0) { $gaps = @('No explicit defensive gaps were generated. Review telemetry coverage before assuming low exposure.') }
    $cards = @()
    foreach ($gap in ($gaps | Select-Object -First 6)) { $cards += "<div class='gap-card'><strong>Priority Review Area</strong><p>$(ConvertTo-SafeHtml $gap)</p></div>" }
    return ($cards -join "`n")
}

function Convert-ExecutiveReasonListToHtml {
    param([hashtable]$Priority)
    $items = @()
    foreach ($reason in @($Priority.Reasons)) { $items += "<li>$(ConvertTo-SafeHtml $reason)</li>" }
    if ($items.Count -eq 0) { $items += '<li>No elevated signal drivers were identified by this run.</li>' }
    return ($items -join "`n")
}

function Export-ExecutiveExposureReport {
    if (-not (Test-CanExportShadowTraceReport)) { return $null }
    if (-not $Script:Investigation) { return $null }
    try {
        $upn = $Script:Investigation.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($upn)) { $upn = 'UnknownUser' }
        $safeName = $upn.Replace('@','_').Replace('.','_').Replace('\','_').Replace('/','_')
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $executiveFile = Join-Path $Script:ReportPath "ShadowTraceOps-ExecutiveReport-$safeName-$timestamp.html"
        $counts = Get-ExecutiveReportMetricCounts
        $priority = Get-ExecutivePriorityModel -Counts $counts
        $barsHtml = Convert-ExecutiveExposureBarsToHtml -Counts $counts
        $timelineHtml = Convert-ExecutivePriorityTimelineToHtml
        $gapHtml = Convert-ExecutiveGapCardsToHtml
        $reasonsHtml = Convert-ExecutiveReasonListToHtml -Priority $priority
        $logoHtml = Get-LogoHtml
        $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $html = @"
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Shadow Trace Ops Executive Report</title><style>
body{margin:0;padding:28px;background:#05070d;color:#f4f1ff;font-family:Segoe UI,Arial,sans-serif}.shell{max-width:1360px;margin:0 auto}.hero,.panel,.kpi,.gap-card{background:linear-gradient(180deg,rgba(22,24,36,.96),rgba(8,10,18,.98));border:1px solid #56336f;border-radius:18px;box-shadow:0 0 30px rgba(0,0,0,.28)}.hero{padding:30px 34px;border-left:6px solid #b26cff;display:grid;grid-template-columns:1fr 150px;gap:20px;align-items:center}h1{font-size:42px;margin:0;color:#fff}.ops{color:#b26cff}.subtitle{color:#d7c4ef;margin-top:7px}.tool-logo{max-width:125px;max-height:125px;object-fit:contain}.meta{margin-top:16px}.meta span{color:#c27cff;font-weight:900}.kpis{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;margin:18px 0}.kpi{padding:18px}.kpi span{display:block;color:#c27cff;text-transform:uppercase;font-size:12px;font-weight:900}.kpi strong{font-size:34px;color:#fff;display:block;margin-top:8px}.grid{display:grid;grid-template-columns:1.1fr .9fr;gap:18px}.panel{padding:20px;margin-bottom:18px}h2{color:#c27cff;text-transform:uppercase;margin:0 0 16px;font-size:20px}.bar-row{display:grid;grid-template-columns:160px 1fr 50px;gap:10px;align-items:center;margin:12px 0}.bar-label{font-weight:800}.bar-track{height:16px;background:rgba(255,255,255,.09);border-radius:999px;overflow:hidden}.bar-track span{display:block;height:100%;background:linear-gradient(90deg,#7c3aed,#d08cff);border-radius:999px}.bar-num{font-weight:900}.bar-desc{grid-column:2/4;color:#d7c4ef;font-size:12px}.timeline-item{display:grid;grid-template-columns:110px 1fr;gap:14px;margin-bottom:16px}.timeline-date{color:#ffd86b;font-weight:900}.timeline-card{border-left:3px solid #b26cff;padding-left:14px}.timeline-card h3{margin:0 0 8px;color:#fff}.timeline-card span{display:inline-block;border:1px solid #56336f;border-radius:999px;padding:4px 9px;color:#ffd86b;margin-right:6px;font-size:12px}.timeline-card p{color:#f4f1ff}.timeline-card small{color:#d7c4ef}.gap-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}.gap-card{padding:14px}.gap-card strong{color:#ffd86b}.gap-card p{line-height:1.45}.guidance li{margin-bottom:9px;line-height:1.45}.footer{color:#bdb2d0;border-top:1px solid #3b284d;margin-top:18px;padding-top:14px;display:flex;justify-content:space-between}@media(max-width:1100px){.grid,.kpis,.gap-grid{grid-template-columns:1fr}.hero{grid-template-columns:1fr}.bar-row{grid-template-columns:1fr}.bar-desc{grid-column:auto}}
</style></head><body><div class="shell">
<div class="hero"><div><h1>SHADOW TRACE <span class="ops">OPS</span></h1><div class="subtitle">Executive Report: Exposure, Priority Changes, Timeline, and Decision Data</div><div class="meta"><span>Target:</span> $(ConvertTo-SafeHtml $upn) &nbsp; <span>Generated:</span> $generated &nbsp; <span>Lookback:</span> $($Script:Investigation.AuthLookbackDays) day(s)</div></div><div>$logoHtml</div></div>
<div class="kpis"><div class="kpi"><span>Executive Score</span><strong>$($priority.Score)</strong></div><div class="kpi"><span>Priority</span><strong>$($priority.Classification)</strong></div><div class="kpi"><span>Total Signals</span><strong>$($counts.Total)</strong></div><div class="kpi"><span>Gaps</span><strong>$($counts.Gaps)</strong></div><div class="kpi"><span>Coverage</span><strong>$($counts.CoveragePct)%</strong></div></div>
<div class="grid"><div><div class="panel"><h2>Exposure by Area</h2>$barsHtml</div><div class="panel"><h2>Gaps Found</h2><div class="gap-grid">$gapHtml</div></div></div><div><div class="panel"><h2>C-Level Decision Guidance</h2><ul class="guidance"><li><strong>Recommended Priority:</strong> $(ConvertTo-SafeHtml $($priority.Priority))</li><li><strong>Classification:</strong> $(ConvertTo-SafeHtml $($priority.Classification))</li><li><strong>Confidence:</strong> $(ConvertTo-SafeHtml $($priority.Confidence))</li><li><strong>Decision:</strong> Prioritize validation of identity, endpoint, session control, OAuth, DLP and telemetry gaps before assuming low exposure.</li></ul><h2>Priority Drivers</h2><ul class="guidance">$reasonsHtml</ul></div><div class="panel"><h2>Recommended Priority Timeline</h2>$timelineHtml</div></div></div>
<div class="footer"><span>Shadow Trace Ops · Executive Report</span><span>No pop-out blades · Executive-ready summary</span></div></div></body></html>
"@
        $html | Out-File -FilePath $executiveFile -Encoding UTF8
        Test-ShadowTraceHtmlReportFile -Path $executiveFile -ReportName 'Executive report' | Out-Null
        $Script:CurrentSnapshotReport = $executiveFile
        $Script:CurrentReportFile = $executiveFile
        Write-ToolLog "Executive report exported: $executiveFile" 'SUCCESS'
        return $executiveFile
    }
    catch {
        Write-ToolLog "Executive report export failed: $($_.Exception.Message)" 'ERROR'
        return $null
    }
}

function Export-ExecutiveReport {
    return Export-ExecutiveExposureReport
}


function Get-SimpleDashboardCss {
@"
html { scroll-behavior: smooth; }
body {
    margin: 0;
    padding: 24px;
    font-family: Segoe UI, Arial, sans-serif;
    color: #f4f1ff;
    background:
        radial-gradient(circle at top left, rgba(123,63,171,.35), transparent 35%),
        radial-gradient(circle at top right, rgba(64,32,96,.30), transparent 35%),
        #07080f;
}
.shell { max-width: 1500px; margin: 0 auto; }
.hero, .panel, .card, details {
    background: linear-gradient(180deg, rgba(22,24,36,.96), rgba(8,10,18,.98));
    border: 1px solid #56336f;
    border-radius: 18px;
    box-shadow: 0 0 30px rgba(0,0,0,.28);
}
.hero {
    display: grid;
    grid-template-columns: 1fr 260px;
    gap: 20px;
    padding: 28px 32px;
    border-left: 6px solid #b26cff;
}
h1 { margin: 0; font-size: 42px; letter-spacing: .5px; }
.ops { color: #b26cff; }
.subtitle { color: #d7c4ef; margin-top: 8px; font-size: 15px; }
.logo-area { display:flex; align-items:center; justify-content:flex-end; gap:14px; }
.tool-logo { max-width: 118px; max-height: 118px; object-fit: contain; filter: drop-shadow(0 0 18px rgba(178,108,255,.45)); }
.tenant-logo, .tenant-logo-placeholder { display:none; }
.meta {
    display:grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
    margin-top: 18px;
}
.meta div {
    background: rgba(255,255,255,.035);
    border: 1px solid #3b284d;
    border-radius: 12px;
    padding: 10px;
}
.meta span { display:block; color:#b26cff; font-weight:800; font-size:12px; margin-bottom:4px; }
.grid {
    display:grid;
    grid-template-columns: 260px 1fr 330px;
    gap: 18px;
    margin-top: 18px;
    align-items:start;
}
.left, .right { position: sticky; top: 18px; display:grid; gap: 12px; }
.panel { padding: 16px; }
.panel h2, details summary, .card h2 { margin:0 0 12px 0; color:#c27cff; font-size:18px; text-transform:uppercase; letter-spacing:.3px; }
.module-link {
    display:flex; justify-content:space-between; align-items:center;
    color:#fff; text-decoration:none; background:rgba(255,255,255,.035);
    border:1px solid #3b284d; border-radius:12px; padding:12px; margin:8px 0;
}
.module-link:hover { border-color:#b26cff; background:rgba(178,108,255,.12); }
.module-count { background:#231631; border:1px solid #56336f; border-radius:999px; padding:3px 8px; color:#fff; font-weight:800; }
.metrics { display:grid; grid-template-columns: repeat(6, 1fr); gap: 12px; margin-bottom:18px; }
.metric {
    background: linear-gradient(180deg, rgba(54,27,76,.65), rgba(10,12,20,.92));
    border:1px solid #56336f; border-radius:16px; padding:18px 10px; text-align:center;
}
.metric .label { color:#d7c4ef; font-size:12px; margin-top:4px; }
.metric .num { font-size:32px; font-weight:900; color:#fff; }
.metric .icon { color:#b26cff; font-weight:900; font-size:12px; margin-bottom:8px; }
.main-two { display:grid; grid-template-columns: 1.15fr .85fr; gap:18px; }
.card { padding: 18px; margin-bottom:18px; }
.donut-wrap { display:grid; grid-template-columns: 250px 1fr; gap:18px; align-items:center; }
.donut {
    width:235px; height:235px; border-radius:50%; display:grid; place-items:center;
    box-shadow: inset 0 0 16px rgba(0,0,0,.5), 0 0 24px rgba(178,108,255,.18);
}
.hole {
    width:110px; height:110px; border-radius:50%; background:#080911; border:1px solid #3b284d;
    display:flex; flex-direction:column; align-items:center; justify-content:center;
}
.hole strong { font-size:32px; }
.hole span { color:#d7c4ef; font-size:12px; text-align:center; }
.legend { display:grid; gap:8px; }
.legend-row {
    display:grid; grid-template-columns:14px 1fr 55px 50px; gap:8px; align-items:center;
    color:#fff; text-decoration:none; border-bottom:1px solid rgba(255,255,255,.08); padding-bottom:8px;
}
.dot { width:12px; height:12px; border-radius:3px; display:inline-block; }
.priority-pair { display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-top:14px; }
.priority {
    text-decoration:none; color:#fff; display:block; border-radius:14px; padding:14px; background:rgba(255,255,255,.035); border:1px solid #3b284d;
}
.priority.first { border-color:#2f80ed; }
.priority.second { border-color:#f2994a; }
.priority span { display:block; color:#d7c4ef; font-size:12px; text-transform:uppercase; font-weight:800; }
.priority strong { display:block; margin-top:4px; }
.score-grid { display:grid; grid-template-columns: repeat(3, 1fr); gap:10px; }
.score-box { border:1px solid #3b284d; border-radius:12px; padding:12px; text-align:center; background:rgba(255,255,255,.035); }
.score-box strong { display:block; font-size:24px; color:#fff; }
.score-box span { color:#d7c4ef; font-size:12px; }
.report-card {
    border:1px solid #3b284d; border-left:4px solid #8a57c2; border-radius:12px;
    padding:12px; margin-bottom:10px; background:rgba(255,255,255,.035); line-height:1.45; overflow-wrap:anywhere;
}
.status-tag {
    display:inline-block; padding:3px 7px; margin-right:7px; border-radius:999px; font-size:10px; font-weight:900; text-transform:uppercase;
}
.tag-normal { background:rgba(46,204,113,.15); color:#6ee7a0; border:1px solid rgba(46,204,113,.4); }
.tag-review { background:rgba(241,196,15,.15); color:#ffd86b; border:1px solid rgba(241,196,15,.4); }
.tag-investigate { background:rgba(255,92,92,.15); color:#ff8d8d; border:1px solid rgba(255,92,92,.4); }
.tag-validate { background:rgba(178,108,255,.15); color:#d4a8ff; border:1px solid rgba(178,108,255,.4); }
details { margin-bottom:14px; overflow:hidden; }
details summary { cursor:pointer; list-style:none; padding:16px 18px; margin:0; }
details summary::-webkit-details-marker { display:none; }
.detail-body { padding:0 18px 18px 18px; }
table { width:100%; border-collapse:collapse; }
th, td { border:1px solid #3b284d; padding:9px; text-align:left; overflow-wrap:anywhere; }
th { color:#c27cff; background:rgba(255,255,255,.04); width:220px; }
.actions a {
    display:block; text-decoration:none; color:#fff; border:1px solid #3b284d; background:rgba(255,255,255,.035);
    border-radius:12px; padding:11px; margin:8px 0;
}
.actions a:hover { border-color:#b26cff; color:#d4a8ff; }
.footer { margin-top:18px; color:#bdb2d0; border-top:1px solid #3b284d; padding-top:14px; display:flex; justify-content:space-between; }

.report-summary-panel {
  overflow: hidden;
}
.summary-kv {
  border:1px solid #3b284d;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:10px;
}
.summary-kv span {
  display:block;
  color:#c27cff;
  font-size:12px;
  font-weight:800;
  text-transform:uppercase;
  letter-spacing:.3px;
  margin-bottom:4px;
}
.summary-kv strong {
  display:block;
  color:#fff;
  font-size:13px;
  line-height:1.35;
  font-weight:600;
  overflow-wrap:anywhere;
  word-break:normal;
}
.right {
  min-width:0;
}
.right .panel {
  min-width:0;
  overflow:hidden;
}


.playbook-grid { display:grid; grid-template-columns:repeat(2,1fr); gap:12px; }
.playbook-card {
  border:1px solid #3b284d;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:12px;
  margin-bottom:10px;
}
.playbook-card div { display:flex; justify-content:space-between; gap:10px; align-items:center; }
.playbook-card strong { color:#fff; }
.playbook-card span {
  color:#ffd86b;
  border:1px solid rgba(241,196,15,.4);
  background:rgba(241,196,15,.12);
  border-radius:999px;
  padding:3px 8px;
  font-size:11px;
  font-weight:800;
}
.playbook-card p { color:#d7c4ef; line-height:1.45; margin:8px 0; }
.playbook-card small { color:#bdb2d0; }


.score-card-panel {
  min-height: 360px;
}
.risk-meter {
  position: relative;
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  gap: 4px;
  margin-top: 16px;
  padding-bottom: 18px;
}
.risk-band {
  height: 58px;
  border-radius: 10px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  border: 1px solid rgba(255,255,255,.12);
  font-weight: 900;
}
.risk-band span {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: .4px;
}
.risk-band small {
  margin-top: 3px;
  color: rgba(255,255,255,.78);
}
.risk-band.low { background: rgba(46,204,113,.16); color: #6ee7a0; }
.risk-band.medium { background: rgba(241,196,15,.16); color: #ffd86b; }
.risk-band.high { background: rgba(255,152,67,.16); color: #ffb86b; }
.risk-band.critical { background: rgba(255,92,92,.16); color: #ff8d8d; }
.risk-needle {
  position: absolute;
  bottom: 3px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ffffff;
  border: 2px solid #b26cff;
  box-shadow: 0 0 14px rgba(178,108,255,.75);
  transform: translateX(-50%);
}
.risk-definitions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin-top: 8px;
}
.risk-definitions div {
  border: 1px solid #3b284d;
  border-radius: 10px;
  background: rgba(255,255,255,.035);
  padding: 8px;
  font-size: 12px;
  color: #d7c4ef;
  line-height: 1.35;
}
.risk-definitions strong {
  color: #ffffff;
}
.score-reasons {
  margin-top: 12px;
}
.score-reasons h3 {
  color: #c27cff;
  font-size: 13px;
  margin: 0 0 8px 0;
  text-transform: uppercase;
  letter-spacing: .3px;
}
.score-reason {
  border-left: 3px solid #b26cff;
  background: rgba(255,255,255,.035);
  border-radius: 8px;
  padding: 7px 9px;
  margin-bottom: 6px;
  font-size: 12px;
  color: #f4f1ff;
}


.score-priority-explainer {
  margin-top: 12px;
  display: grid;
  gap: 10px;
}
.explainer-card {
  border:1px solid #3b284d;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:11px 12px;
}
.explainer-card span {
  display:block;
  color:#c27cff;
  font-size:12px;
  font-weight:900;
  text-transform:uppercase;
  letter-spacing:.35px;
  margin-bottom:5px;
}
.explainer-card strong {
  display:block;
  color:#fff;
  font-size:13px;
  margin-bottom:4px;
}
.explainer-card small {
  color:#d7c4ef;
  line-height:1.35;
  display:block;
}
.explainer-card.score-critical {
  border-left:4px solid #ff5c5c;
}
.explainer-card.score-high {
  border-left:4px solid #ffb86b;
}
.explainer-card.score-medium {
  border-left:4px solid #ffd86b;
}
.explainer-card.score-low {
  border-left:4px solid #6ee7a0;
}
.explainer-card.priority-card-note {
  border-left:4px solid #b26cff;
}


.playbook-card-grid {
  display:grid;
  grid-template-columns:repeat(2, minmax(0, 1fr));
  gap:12px;
}
.playbook-open-card {
  text-align:left;
  border:1px solid #3b284d;
  border-left:4px solid #b26cff;
  border-radius:14px;
  background:rgba(255,255,255,.04);
  color:#fff;
  padding:13px 14px;
  cursor:pointer;
  font-family:inherit;
  transition: all .15s ease;
}
.playbook-open-card:hover {
  transform: translateY(-1px);
  border-color:#b26cff;
  background:rgba(178,108,255,.12);
  box-shadow:0 0 18px rgba(178,108,255,.16);
}
.playbook-open-card .pb-title {
  display:block;
  font-weight:900;
  color:#fff;
  margin-bottom:6px;
}
.playbook-open-card .pb-meta {
  display:inline-block;
  color:#ffd86b;
  border:1px solid rgba(241,196,15,.4);
  background:rgba(241,196,15,.12);
  border-radius:999px;
  padding:3px 8px;
  font-size:11px;
  font-weight:900;
  margin-bottom:7px;
}
.playbook-open-card small {
  display:block;
  color:#d7c4ef;
  line-height:1.35;
}
.playbook-data-store { display:none; }
.playbook-overlay {
  position:fixed;
  inset:0;
  background:rgba(0,0,0,.52);
  opacity:0;
  pointer-events:none;
  transition:opacity .18s ease;
  z-index:9998;
}
.playbook-overlay.open {
  opacity:1;
  pointer-events:auto;
}
.playbook-drawer {
  position:fixed;
  top:0;
  right:-520px;
  width:500px;
  max-width:92vw;
  height:100vh;
  background:linear-gradient(180deg,#17131f,#080911);
  border-left:1px solid #56336f;
  box-shadow:-18px 0 38px rgba(0,0,0,.38);
  z-index:9999;
  transition:right .2s ease;
  padding:22px;
  overflow-y:auto;
  box-sizing:border-box;
}
.playbook-drawer.open { right:0; }
.drawer-close {
  float:right;
  border:1px solid #56336f;
  background:#281536;
  color:#fff;
  border-radius:999px;
  padding:7px 12px;
  cursor:pointer;
}
.drawer-header {
  margin-top:28px;
  border-bottom:1px solid #3b284d;
  padding-bottom:16px;
}
.drawer-severity {
  display:inline-block;
  color:#ffd86b;
  border:1px solid rgba(241,196,15,.4);
  background:rgba(241,196,15,.12);
  border-radius:999px;
  padding:4px 10px;
  font-size:12px;
  font-weight:900;
  text-transform:uppercase;
}
.drawer-header h2 {
  color:#fff;
  margin:12px 0 4px 0;
  font-size:24px;
}
.drawer-header p {
  color:#bdb2d0;
  margin:0;
}
.drawer-section {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  margin-top:14px;
  padding:14px;
}
.drawer-section h4 {
  margin:0 0 8px 0;
  color:#c27cff;
  text-transform:uppercase;
  font-size:13px;
  letter-spacing:.3px;
}
.drawer-section p {
  color:#f4f1ff;
  line-height:1.5;
}
.drawer-steps {
  list-style:none;
  padding:0;
  margin:0;
  display:grid;
  gap:10px;
}
.drawer-steps li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
  align-items:start;
}
.drawer-steps li span {
  width:26px;
  height:26px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.drawer-steps li p {
  margin:2px 0 0 0;
  color:#f4f1ff;
  line-height:1.45;
}
.drawer-section pre {
  white-space:pre-wrap;
  word-break:break-word;
  background:#06070d;
  border:1px solid #3b284d;
  border-radius:12px;
  padding:12px;
  color:#e8ddff;
  font-size:12px;
}
.drawer-muted { color:#bdb2d0; }
.playbook-empty {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:12px;
  background:rgba(255,255,255,.035);
}

.kql-block { margin-top:10px; }
.kql-title { color:#ffd86b; font-weight:900; margin:8px 0 6px 0; font-size:12px; }
.kql-block pre { white-space:pre-wrap; word-break:break-word; background:#06070d; border:1px solid #3b284d; border-radius:12px; padding:12px; color:#e8ddff; font-size:12px; }


.analyst-workflow-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:14px;
  margin-bottom:12px;
}
.analyst-workflow-card h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:14px;
  margin:0 0 8px 0;
  letter-spacing:.3px;
}
.analyst-workflow-card p {
  white-space:pre-wrap;
  color:#f4f1ff;
  line-height:1.5;
  margin:0;
}
.timeline-note {
  border-left:4px solid #b26cff;
  background:rgba(255,255,255,.035);
  border-radius:12px;
  padding:10px 12px;
  margin-bottom:10px;
}
.timeline-note strong {
  display:block;
  color:#ffd86b;
  font-size:12px;
  margin-bottom:4px;
}
.timeline-note p {
  margin:0;
  color:#f4f1ff;
}


.analyst-live-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:linear-gradient(180deg, rgba(38,22,55,.72), rgba(11,12,20,.95));
  padding:16px;
}
.analyst-live-header {
  display:flex;
  justify-content:space-between;
  gap:16px;
  align-items:flex-start;
  margin-bottom:14px;
}
.analyst-live-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:16px;
  margin:0 0 6px 0;
  letter-spacing:.3px;
}
.analyst-live-header p {
  color:#d7c4ef;
  margin:0;
  line-height:1.45;
}
.report-save-button {
  border:1px solid #b26cff;
  background:#281536;
  color:#fff;
  border-radius:999px;
  padding:9px 14px;
  cursor:pointer;
  font-weight:800;
  white-space:nowrap;
}
.report-save-button:hover {
  background:#3b1d55;
  box-shadow:0 0 16px rgba(178,108,255,.22);
}
.analyst-label {
  display:block;
  color:#ffd86b;
  font-size:12px;
  text-transform:uppercase;
  font-weight:900;
  margin:12px 0 6px 0;
}
.analyst-textarea {
  width:100%;
  min-height:82px;
  resize:vertical;
  box-sizing:border-box;
  border:1px solid #3b284d;
  border-radius:12px;
  background:#06070d;
  color:#f4f1ff;
  padding:12px;
  font-family:Segoe UI, Arial, sans-serif;
  font-size:13px;
  line-height:1.45;
}
.analyst-textarea.notes {
  min-height:140px;
}
.workflow-check-grid {
  display:grid;
  grid-template-columns:repeat(3, 1fr);
  gap:10px;
  margin-top:14px;
}
.workflow-check-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  font-size:12px;
}
.workflow-check-grid input {
  accent-color:#b26cff;
}
.embedded-analyst-summary {
  margin-top:14px;
  border:1px dashed #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
}
.embedded-analyst-summary h3 {
  color:#c27cff;
  margin:0 0 8px 0;
  text-transform:uppercase;
  font-size:13px;
}
.embedded-analyst-summary p,
.embedded-analyst-summary li {
  color:#f4f1ff;
  white-space:pre-wrap;
}

.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){
  .workflow-check-grid { grid-template-columns:1fr; }
  .analyst-live-header { display:block; }
  .report-save-button { margin-top:12px; }
}


.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){
  .playbook-card-grid { grid-template-columns:1fr; }
}


.kql-block { margin-top:10px; }
.kql-title { color:#ffd86b; font-weight:900; margin:8px 0 6px 0; font-size:12px; }
.kql-block pre { white-space:pre-wrap; word-break:break-word; background:#06070d; border:1px solid #3b284d; border-radius:12px; padding:12px; color:#e8ddff; font-size:12px; }


.analyst-workflow-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:14px;
  margin-bottom:12px;
}
.analyst-workflow-card h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:14px;
  margin:0 0 8px 0;
  letter-spacing:.3px;
}
.analyst-workflow-card p {
  white-space:pre-wrap;
  color:#f4f1ff;
  line-height:1.5;
  margin:0;
}
.timeline-note {
  border-left:4px solid #b26cff;
  background:rgba(255,255,255,.035);
  border-radius:12px;
  padding:10px 12px;
  margin-bottom:10px;
}
.timeline-note strong {
  display:block;
  color:#ffd86b;
  font-size:12px;
  margin-bottom:4px;
}
.timeline-note p {
  margin:0;
  color:#f4f1ff;
}


.analyst-live-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:linear-gradient(180deg, rgba(38,22,55,.72), rgba(11,12,20,.95));
  padding:16px;
}
.analyst-live-header {
  display:flex;
  justify-content:space-between;
  gap:16px;
  align-items:flex-start;
  margin-bottom:14px;
}
.analyst-live-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:16px;
  margin:0 0 6px 0;
  letter-spacing:.3px;
}
.analyst-live-header p {
  color:#d7c4ef;
  margin:0;
  line-height:1.45;
}
.report-save-button {
  border:1px solid #b26cff;
  background:#281536;
  color:#fff;
  border-radius:999px;
  padding:9px 14px;
  cursor:pointer;
  font-weight:800;
  white-space:nowrap;
}
.report-save-button:hover {
  background:#3b1d55;
  box-shadow:0 0 16px rgba(178,108,255,.22);
}
.analyst-label {
  display:block;
  color:#ffd86b;
  font-size:12px;
  text-transform:uppercase;
  font-weight:900;
  margin:12px 0 6px 0;
}
.analyst-textarea {
  width:100%;
  min-height:82px;
  resize:vertical;
  box-sizing:border-box;
  border:1px solid #3b284d;
  border-radius:12px;
  background:#06070d;
  color:#f4f1ff;
  padding:12px;
  font-family:Segoe UI, Arial, sans-serif;
  font-size:13px;
  line-height:1.45;
}
.analyst-textarea.notes {
  min-height:140px;
}
.workflow-check-grid {
  display:grid;
  grid-template-columns:repeat(3, 1fr);
  gap:10px;
  margin-top:14px;
}
.workflow-check-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  font-size:12px;
}
.workflow-check-grid input {
  accent-color:#b26cff;
}
.embedded-analyst-summary {
  margin-top:14px;
  border:1px dashed #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
}
.embedded-analyst-summary h3 {
  color:#c27cff;
  margin:0 0 8px 0;
  text-transform:uppercase;
  font-size:13px;
}
.embedded-analyst-summary p,
.embedded-analyst-summary li {
  color:#f4f1ff;
  white-space:pre-wrap;
}

.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){
  .workflow-check-grid { grid-template-columns:1fr; }
  .analyst-live-header { display:block; }
  .report-save-button { margin-top:12px; }
}


.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){ .grid{grid-template-columns:1fr;} .left,.right{position:static;} .main-two{grid-template-columns:1fr;} .metrics{grid-template-columns:repeat(2,1fr);} .hero{grid-template-columns:1fr;} .meta{grid-template-columns:1fr 1fr;} }
"@
}

function Get-SimpleRiskCounts {
    return [ordered]@{
        Identity = if ($Script:Investigation.IdentityRisk) { $Script:Investigation.IdentityRisk.Count } else { 0 }
        Authentication = if ($Script:Investigation.Authentication) { $Script:Investigation.Authentication.Count } else { 0 }
        "Email / URL" = @($Script:Investigation.EmailContext + $Script:Investigation.UrlClickContext).Count
        "Endpoint / XDR" = @($Script:Investigation.EndpointContext + $Script:Investigation.Alerts + $Script:Investigation.Incidents).Count
        "Cloud Activity" = @($Script:Investigation.CloudActivity + $Script:Investigation.CloudAppEvents).Count
        OAuth = if ($Script:Investigation.OAuthActivity) { $Script:Investigation.OAuthActivity.Count } else { 0 }
        Gaps = if ($Script:Investigation.PotentialGaps) { $Script:Investigation.PotentialGaps.Count } else { 0 }
    }
}

function Get-SimpleDonutHtml {
    $counts = Get-SimpleRiskCounts
    $items = @()
    foreach ($k in $counts.Keys) { if ([int]$counts[$k] -gt 0) { $items += [pscustomobject]@{Name=$k;Count=[int]$counts[$k]} } }

    if ($items.Count -eq 0) {
        $items = @([pscustomobject]@{Name="No elevated signals";Count=1})
    }

    $total = ($items | Measure-Object -Property Count -Sum).Sum
    $colors = @("#2f80ed","#f2994a","#eb5757","#27ae60","#9b51e0","#00bcd4","#f2c94c")
    $start = 0
    $segments = @()
    $legend = @()
    for ($i=0; $i -lt $items.Count; $i++) {
        $pct = [math]::Round(($items[$i].Count / $total) * 100, 1)
        $end = $start + $pct
        $color = $colors[$i % $colors.Count]
        $segments += "$color $start% $end%"
        $anchor = ($items[$i].Name -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLower()
        $legend += "<a class='legend-row' href='#$anchor'><span class='dot' style='background:$color'></span><span>$(ConvertTo-SafeHtml $items[$i].Name)</span><strong>$pct%</strong><small>($($items[$i].Count))</small></a>"
        $start = $end
    }

    $top = $items | Sort-Object Count -Descending | Select-Object -First 2
    if ($top.Count -eq 1) { $second = $top[0] } else { $second = $top[1] }

    return @"
<div class='card'>
  <h2>Where to Start</h2>
  <div class='donut-wrap'>
    <div class='donut' style='background:conic-gradient($($segments -join ', '));'><div class='hole'><strong>$total</strong><span>Total Signals</span></div></div>
    <div class='legend'>$($legend -join "`n")</div>
  </div>
  <div class='priority-pair'>
    <a class='priority first' href='#'><span>Top Priority</span><strong>$(ConvertTo-SafeHtml $top[0].Name)</strong><small>$($top[0].Count) signal(s)</small></a>
    <a class='priority second' href='#'><span>Second Pivot</span><strong>$(ConvertTo-SafeHtml $second.Name)</strong><small>$($second.Count) signal(s)</small></a>
  </div>
</div>
"@
}

function Get-SimpleCardsHtml {
    $counts = Get-SimpleRiskCounts
    return @"
<div class='metrics'>
  <div class='metric'><div class='icon'>AUTH</div><div class='num'>$($counts.Authentication)</div><div class='label'>Auth Items</div></div>
  <div class='metric'><div class='icon'>RISK</div><div class='num'>$($counts.Identity)</div><div class='label'>Risk Items</div></div>
  <div class='metric'><div class='icon'>CLOUD</div><div class='num'>$($counts['Cloud Activity'])</div><div class='label'>Cloud Items</div></div>
  <div class='metric'><div class='icon'>XDR</div><div class='num'>$($counts['Endpoint / XDR'])</div><div class='label'>XDR/Endpoint</div></div>
  <div class='metric'><div class='icon'>URL</div><div class='num'>$($counts['Email / URL'])</div><div class='label'>Email/URL</div></div>
  <div class='metric'><div class='icon'>GAPS</div><div class='num'>$($counts.Gaps)</div><div class='label'>Potential Gaps</div></div>
</div>
"@
}

function Get-SimpleModuleNavHtml {
    $counts = Get-SimpleRiskCounts
    $links = foreach ($k in $counts.Keys) {
        $anchor = ($k -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLower()
        "<a class='module-link' href='#$anchor'><span>$(ConvertTo-SafeHtml $k)</span><span class='module-count'>$($counts[$k])</span></a>"
    }
    return "<div class='panel'><h2>Modules</h2>$($links -join "`n")</div>"
}

function Get-SimpleScoreHtml {
    if (Get-Command Invoke-InvestigationScoring -ErrorAction SilentlyContinue) {
        Invoke-InvestigationScoring
    }
    $score = if ($Script:Investigation.InvestigationScore) { $Script:Investigation.InvestigationScore } else { 0 }
    $class = if ($Script:Investigation.ScoreClassification) { $Script:Investigation.ScoreClassification } else { "Low" }
    $confidence = if ($Script:Investigation.ConfidenceLevel) { $Script:Investigation.ConfidenceLevel } else { "Low" }
    return @"
<div class='card'>
  <h2>Investigation Score</h2>
  <div class='score-grid'>
    <div class='score-box'><strong>$score</strong><span>Score</span></div>
    <div class='score-box'><strong>$class</strong><span>Classification</span></div>
    <div class='score-box'><strong>$confidence</strong><span>Confidence</span></div>
  </div>
</div>
"@
}

function Export-ShadowTraceDashboardReport {
    try {
        $upn = $Script:Investigation.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($upn)) { $upn = "UnknownUser" }
        $safeName = $upn.Replace("@","_").Replace(".","_").Replace("\","_").Replace("/","_")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportFile = Join-Path $Script:ReportPath "ShadowTraceOps-Dashboard-$safeName-$timestamp.html"

        $css = Get-SimpleDashboardCss
        $logoHtml = Get-LogoHtml
        $metricCards = Get-SimpleCardsHtml
        $donut = Get-SimpleDonutHtml
        $score = Get-SimpleScoreHtml
        $modules = Get-SimpleModuleNavHtml
        $summary = ConvertTo-HtmlTableFromHashtable $Script:Investigation.UserSummary
        $findings = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.ObservedRisks + $Script:Investigation.PotentialGaps + $Script:Investigation.InvestigationPivots) -MaxItems 6 -EmptyMessage "No elevated findings were generated."
        $recommendations = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Recommendations -MaxItems 5 -EmptyMessage "No recommendations were generated."
        $identity = ConvertTo-ReportCardsHtml -Items $Script:Investigation.IdentityRisk -MaxItems 8
        $auth = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Authentication -MaxItems 8
        $email = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.EmailContext + $Script:Investigation.UrlClickContext) -MaxItems 8
        $xdr = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.EndpointContext + $Script:Investigation.Alerts + $Script:Investigation.Incidents) -MaxItems 8
        $cloud = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.CloudActivity + $Script:Investigation.CloudAppEvents) -MaxItems 8
        $oauth = ConvertTo-ReportCardsHtml -Items $Script:Investigation.OAuthActivity -MaxItems 8
        $gaps = ConvertTo-ReportCardsHtml -Items $Script:Investigation.PotentialGaps -MaxItems 8
        $source = ConvertTo-ReportCardsHtml -Items $Script:Investigation.SourceHealth -MaxItems 8

        $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Shadow Trace Ops Dashboard</title>
<style>$css</style>
</head>
<body>
<div class='shell'>
  <section class='hero'>
    <div>
      <h1>SHADOW TRACE <span class='ops'>OPS</span></h1>
      <div class='subtitle'>Post-authentication investigation, XDR correlation, and defensive gap assessment</div>
      <div class='meta'>
        <div><span>Generated</span>$(Get-Date)</div>
        <div><span>Target User</span>$(ConvertTo-SafeHtml $upn)</div>
        <div><span>Lookback</span>$($Script:Investigation.AuthLookbackDays) day(s)</div>
        <div><span>Run Mode</span>$($Script:Investigation.RunMode)</div>
      </div>
    </div>
    <div class='logo-area'>$logoHtml</div>
  </section>

  <div class='grid'>
    <aside class='left'>$modules</aside>

    <main>
      $metricCards
      <div class='main-two'>
        $donut
        $score
      </div>

      <details open id='executive-summary'><summary>Executive Summary</summary><div class='detail-body'>$summary</div></details>
      <details open id='identity'><summary>Identity Risk</summary><div class='detail-body'>$identity</div></details>
      <details id='authentication'><summary>Authentication</summary><div class='detail-body'>$auth</div></details>
      <details id='email-url'><summary>Email / URL Activity</summary><div class='detail-body'>$email</div></details>
      <details id='endpoint-xdr'><summary>Endpoint / XDR</summary><div class='detail-body'>$xdr</div></details>
      <details id='cloud-activity'><summary>Cloud Activity</summary><div class='detail-body'>$cloud</div></details>
      <details id='oauth'><summary>OAuth / App Access</summary><div class='detail-body'>$oauth</div></details>
      <details id='gaps'><summary>Gaps & Exposures</summary><div class='detail-body'>$gaps</div></details>
      <details id='source-health'><summary>Source Health</summary><div class='detail-body'>$source</div></details>
    </main>

    <aside class='right'>
      <div class='panel'><h2>Report Summary</h2><table><tr><th>User</th><td>$(ConvertTo-SafeHtml $upn)</td></tr><tr><th>Priority</th><td>$(ConvertTo-SafeHtml $Script:Investigation.Priority)</td></tr><tr><th>Profile</th><td>$(ConvertTo-SafeHtml $Script:Investigation.InvestigationProfile)</td></tr><tr><th>Readiness</th><td>$(ConvertTo-SafeHtml $Script:Investigation.ProductReadiness)</td></tr></table></div>
      <div class='panel'><h2>Key Findings</h2>$findings</div>
      <div class='panel'><h2>Recommendations</h2>$recommendations</div>
      <div class='panel actions'><h2>Actions</h2><a href='#executive-summary'>Review Summary</a><a href='#source-health'>Review Source Health</a><a href='#gaps'>Review Gaps</a></div>
    </aside>
  </div>

  <div class='footer'><span>Shadow Trace Ops - Investigate. Correlate. Protect.</span><span>Read-only advisory report.</span></div>
</div>
</body>
</html>
"@

        $html | Out-File -FilePath $reportFile -Encoding UTF8
        Test-ShadowTraceHtmlReportFile -Path $reportFile -ReportName "HTML report" | Out-Null
        Test-ShadowTraceHtmlReportFile -Path $reportFile -ReportName "Primary dashboard report" | Out-Null
        $Script:CurrentReportFile = $reportFile
        Write-ToolLog "Shadow Trace Ops dashboard report exported: $reportFile" "SUCCESS"
        return $reportFile
    }
    catch {
        Write-ToolLog "Dashboard report export failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}




function Get-PlaybookDashboardHtml {
    $playbookFiles = @()
    if ($Script:PlaybookPath -and (Test-Path $Script:PlaybookPath)) {
        $playbookFiles = @(Get-ChildItem -Path $Script:PlaybookPath -Filter "*.json" -ErrorAction SilentlyContinue)
    }

    if (-not $playbookFiles -or $playbookFiles.Count -eq 0) {
        return "<div class='report-card muted-card'><span class='status-tag tag-review'>Playbooks</span>No JSON playbooks were found in Config\\Playbooks.</div>"
    }

    $cards = foreach ($file in $playbookFiles) {
        try {
            $pb = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $area = if ($pb.Area) { $pb.Area } else { $file.BaseName }
            $severity = if ($pb.Severity) { $pb.Severity } else { "Advisory" }
            $why = if ($pb.WhyItMatters) { $pb.WhyItMatters } else { "Investigation guidance is available in this JSON playbook." }

            "<div class='playbook-card'><div><strong>$(ConvertTo-SafeHtml $area)</strong><span>$(ConvertTo-SafeHtml $severity)</span></div><p>$(ConvertTo-SafeHtml $why)</p><small>File: $(ConvertTo-SafeHtml $file.Name)</small></div>"
        }
        catch {
            "<div class='playbook-card'><div><strong>$(ConvertTo-SafeHtml $file.BaseName)</strong><span>Review</span></div><p>Could not parse this playbook JSON.</p><small>File: $(ConvertTo-SafeHtml $file.Name)</small></div>"
        }
    }

    return ($cards -join "`n")
}



function ConvertTo-JsSafeString {
    param([AllowNull()][object]$InputObject)
    if ($null -eq $InputObject) { return "" }
    $value = [string]$InputObject
    $value = $value.Replace("\", "\\")
    $value = $value.Replace("`r`n", "\n")
    $value = $value.Replace("`n", "\n")
    $value = $value.Replace('"', '\"')
    $value = $value.Replace("'", "\'")
    $value = $value.Replace("<", "\u003c")
    $value = $value.Replace(">", "\u003e")
    return $value
}

function Convert-PlaybookArrayToHtml {
    param(
        [array]$Items,
        [string]$EmptyText = "No steps were defined in this playbook."
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return "<li>$(ConvertTo-SafeHtml $EmptyText)</li>"
    }

    $i = 1
    $rows = foreach ($item in $Items) {
        "<li><span>$i</span><p>$(ConvertTo-SafeHtml $item)</p></li>"
        $i++
    }

    return ($rows -join "`n")
}



function ConvertTo-KqlLiteral {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return "" }

    $s = [string]$Value
    $s = $s.Replace("\", "\\")
    $s = $s.Replace('"', '\"')
    return $s
}

function Get-ShadowTraceKqlParameters {
    $targetUser = ""
    $lookbackDays = "30"
    $targetAccount = ""
    $targetDomain = ""

    try {
        if ($Script:Investigation -and $Script:Investigation.UserPrincipalName) {
            $targetUser = [string]$Script:Investigation.UserPrincipalName
        }
    } catch {}

    try {
        if ([string]::IsNullOrWhiteSpace($targetUser) -and $Script:LastResolvedUserPrincipalName) {
            $targetUser = [string]$Script:LastResolvedUserPrincipalName
        }
    } catch {}

    try {
        if ([string]::IsNullOrWhiteSpace($targetUser) -and $Script:txtUser) {
            $targetUser = [string]$Script:txtUser.Text.Trim()
        }
    } catch {}

    try {
        if ($Script:Investigation -and $Script:Investigation.AuthLookbackDays) {
            $lookbackDays = [string][int]$Script:Investigation.AuthLookbackDays
        }
    } catch {}

    try {
        if (($lookbackDays -eq "30" -or [string]::IsNullOrWhiteSpace($lookbackDays)) -and $Script:cmbAuthLookback -and $Script:cmbAuthLookback.SelectedItem) {
            $lookbackDays = [string]([int]($Script:cmbAuthLookback.SelectedItem.ToString().Replace(" days","")))
        }
    } catch {}

    if (-not [string]::IsNullOrWhiteSpace($targetUser) -and $targetUser -match "@") {
        $targetAccount = ($targetUser -split "@")[0]
        $targetDomain = ($targetUser -split "@")[1]
    }

    return [ordered]@{
        TargetUser = $targetUser
        TargetAccount = $targetAccount
        TargetDomain = $targetDomain
        LookbackDays = $lookbackDays
    }
}

function Resolve-ShadowTraceKqlTemplate {
    param([AllowNull()][string]$KqlContent)

    if ([string]::IsNullOrWhiteSpace($KqlContent)) { return "" }

    $params = Get-ShadowTraceKqlParameters

    $targetUser = ConvertTo-KqlLiteral $params.TargetUser
    $targetAccount = ConvertTo-KqlLiteral $params.TargetAccount
    $targetDomain = ConvertTo-KqlLiteral $params.TargetDomain
    $lookbackDays = if ($params.LookbackDays -match '^\d+$') { $params.LookbackDays } else { "30" }

    $resolved = $KqlContent
    $resolved = $resolved.Replace("{TargetUser}", $targetUser)
    $resolved = $resolved.Replace("{TargetAccount}", $targetAccount)
    $resolved = $resolved.Replace("{TargetDomain}", $targetDomain)
    $resolved = $resolved.Replace("{LookbackDays}", $lookbackDays)

    return $resolved
}

function Get-KqlParameterSummaryHtml {
    $params = Get-ShadowTraceKqlParameters
    return @"
<div class="kql-parameter-summary">
  <strong>KQL Template Parameters</strong>
  <span>TargetUser: $(ConvertTo-SafeHtml $params.TargetUser)</span>
  <span>TargetAccount: $(ConvertTo-SafeHtml $params.TargetAccount)</span>
  <span>TargetDomain: $(ConvertTo-SafeHtml $params.TargetDomain)</span>
  <span>LookbackDays: $(ConvertTo-SafeHtml $params.LookbackDays)</span>
</div>
"@
}

function Resolve-ShadowTraceKqlPath {
    param([string]$QueryPath)
    if ([string]::IsNullOrWhiteSpace($QueryPath)) { return $null }
    if ([System.IO.Path]::IsPathRooted($QueryPath) -and (Test-Path $QueryPath)) { return (Resolve-Path $QueryPath).Path }
    $normalized = $QueryPath -replace "/", "\"
    $candidates = @(
        (Join-Path $Script:RootPath $normalized),
        (Join-Path $Script:ConfigPath $normalized),
        (Join-Path $Script:KqlPath $normalized),
        (Join-Path $Script:KqlPath ([System.IO.Path]::GetFileName($normalized)))
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return (Resolve-Path $path).Path }
    }
    return $null
}

function Convert-RelatedQueriesToHtml {
    param([array]$RelatedQueries)

    if (-not $RelatedQueries -or $RelatedQueries.Count -eq 0) {
        return "<p class='drawer-muted'>No KQL was defined for this playbook yet.</p>"
    }

    $blocks = @()
    foreach ($queryRef in $RelatedQueries) {
        $queryName = [string]$queryRef
        $queryPath = Resolve-ShadowTraceKqlPath -QueryPath $queryName

        if ($queryPath) {
            try {
                $queryText = Resolve-ShadowTraceKqlTemplate -KqlContent (Get-Content -Path $queryPath -Raw -Encoding UTF8)
                $blocks += "<div class='kql-block'><div class='kql-title'>$(ConvertTo-SafeHtml $queryName)</div><pre>$(ConvertTo-SafeHtml $queryText)</pre></div>"
            }
            catch {
                $blocks += "<div class='kql-block'><div class='kql-title'>$(ConvertTo-SafeHtml $queryName)</div><p class='drawer-muted'>KQL file was found but could not be read.</p></div>"
            }
        }
        elseif ($queryName -match "\|" -or $queryName -match "where|summarize|project|extend|let") {
            $blocks += "<div class='kql-block'><div class='kql-title'>Inline KQL</div><pre>$(ConvertTo-SafeHtml (Resolve-ShadowTraceKqlTemplate -KqlContent $queryName))</pre></div>"
        }
        else {
            $blocks += "<div class='kql-block'><div class='kql-title'>$(ConvertTo-SafeHtml $queryName)</div><p class='drawer-muted'>Referenced KQL file was not found. Place it under Toolkit\Config\KQL or update RelatedQueries.</p></div>"
        }
    }
    return ($blocks -join "`n")
}

function Get-PlaybookSidePanelHtml {
    $playbookFiles = @()
    if ($Script:PlaybookPath -and (Test-Path $Script:PlaybookPath)) {
        $playbookFiles = @(Get-ChildItem -Path $Script:PlaybookPath -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object Name)
    }

    if (-not $playbookFiles -or $playbookFiles.Count -eq 0) {
        return @"
<div class="playbook-empty">
  <span class="status-tag tag-review">Playbooks</span>
  No JSON playbooks were found in Toolkit\Config\Playbooks.
</div>
"@
    }

    $cards = @()
    $datasets = @()

    foreach ($file in $playbookFiles) {
        try {
            $pb = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json

            $area = if ($pb.Area) { [string]$pb.Area } elseif ($pb.Title) { [string]$pb.Title } else { [string]$file.BaseName }
            $severity = if ($pb.Severity) { [string]$pb.Severity } else { "Advisory" }
            $why = if ($pb.WhyItMatters) { [string]$pb.WhyItMatters } elseif ($pb.Description) { [string]$pb.Description } else { "Investigation guidance is available in this JSON playbook." }
            $triggers = if ($pb.Triggers) { @($pb.Triggers) } else { @() }
            $steps = if ($pb.ReviewSteps) { @($pb.ReviewSteps) } elseif ($pb.InvestigationSteps) { @($pb.InvestigationSteps) } else { @() }
            $actions = if ($pb.RecommendedActions) { @($pb.RecommendedActions) } elseif ($pb.Actions) { @($pb.Actions) } else { @() }
            $queries = if ($pb.RelatedQueries) { @($pb.RelatedQueries) } elseif ($pb.Kql) { @($pb.Kql) } else { @() }

            $id = "pb_" + (($file.BaseName -replace "[^a-zA-Z0-9]", "_").ToLower())
            $triggerText = if ($triggers.Count -gt 0) { ($triggers -join ", ") } else { "General investigation guidance" }

            $stepsHtml = Convert-PlaybookArrayToHtml -Items $steps -EmptyText "No investigation steps were defined."
            $actionsHtml = Convert-PlaybookArrayToHtml -Items $actions -EmptyText "No recommended actions were defined."
            $queryHtml = Convert-RelatedQueriesToHtml -RelatedQueries $queries

            $cards += @"
<button class="playbook-open-card" onclick="openPlaybook('$id')" type="button">
  <span class="pb-title">$(ConvertTo-SafeHtml $area)</span>
  <span class="pb-meta">$(ConvertTo-SafeHtml $severity)</span>
  <small>$(ConvertTo-SafeHtml $triggerText)</small>
</button>
"@

            $datasets += @"
<div id="$id" class="playbook-dataset"
     data-title="$(ConvertTo-SafeHtml $area)"
     data-severity="$(ConvertTo-SafeHtml $severity)"
     data-file="$(ConvertTo-SafeHtml $file.Name)">
  <div class="drawer-section">
    <h4>Why this matters</h4>
    <p>$(ConvertTo-SafeHtml $why)</p>
  </div>
  <div class="drawer-section">
    <h4>Investigation Steps</h4>
    <ol class="drawer-steps">$stepsHtml</ol>
  </div>
  <div class="drawer-section">
    <h4>Recommended Actions</h4>
    <ol class="drawer-steps">$actionsHtml</ol>
  </div>
  <div class="drawer-section">
    <h4>Related KQL / Pivots</h4>
    $queryHtml
  </div>
</div>
"@
        }
        catch {
            $id = "pb_" + (($file.BaseName -replace "[^a-zA-Z0-9]", "_").ToLower())
            $cards += @"
<button class="playbook-open-card" onclick="openPlaybook('$id')" type="button">
  <span class="pb-title">$(ConvertTo-SafeHtml $file.BaseName)</span>
  <span class="pb-meta">Review</span>
  <small>Could not parse JSON.</small>
</button>
"@
            $datasets += @"
<div id="$id" class="playbook-dataset" data-title="$(ConvertTo-SafeHtml $file.BaseName)" data-severity="Review" data-file="$(ConvertTo-SafeHtml $file.Name)">
  <div class="drawer-section">
    <h4>Playbook Load Error</h4>
    <p>This JSON playbook could not be parsed. Review the file formatting in Toolkit\Config\Playbooks.</p>
  </div>
</div>
"@
        }
    }

    return @"
<div class="playbook-card-grid">
$($cards -join "`n")
</div>

<div class="playbook-data-store" aria-hidden="true">
$($datasets -join "`n")
</div>

<div id="playbookOverlay" class="playbook-overlay" onclick="closePlaybook()"></div>
<aside id="playbookDrawer" class="playbook-drawer" aria-hidden="true">
  <button class="drawer-close" onclick="closePlaybook()" type="button">Close</button>
  <div class="drawer-header">
    <span id="drawerSeverity" class="drawer-severity">Advisory</span>
    <h2 id="drawerTitle">Investigation Playbook</h2>
    <p id="drawerFile">JSON playbook guidance</p>
  </div>
  <div id="drawerBody" class="drawer-body"></div>
</aside>

<script>
function openPlaybook(id) {
  var source = document.getElementById(id);
  var drawer = document.getElementById('playbookDrawer');
  var overlay = document.getElementById('playbookOverlay');
  if (!source || !drawer || !overlay) { return; }
  document.getElementById('drawerTitle').textContent = source.getAttribute('data-title') || 'Investigation Playbook';
  document.getElementById('drawerSeverity').textContent = source.getAttribute('data-severity') || 'Advisory';
  document.getElementById('drawerFile').textContent = source.getAttribute('data-file') || 'JSON playbook';
  document.getElementById('drawerBody').innerHTML = source.innerHTML;
  drawer.classList.add('open');
  overlay.classList.add('open');
  drawer.setAttribute('aria-hidden','false');
}
function closePlaybook() {
  var drawer = document.getElementById('playbookDrawer');
  var overlay = document.getElementById('playbookOverlay');
  if (!drawer || !overlay) { return; }
  drawer.classList.remove('open');
  overlay.classList.remove('open');
  drawer.setAttribute('aria-hidden','true');
}
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') { closePlaybook(); }
});
</script>
"@
}



function Test-ShadowTraceHtmlReportFile {
    param(
        [string]$Path,
        [string]$ReportName = "HTML report"
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        Write-ToolLog "$ReportName validation failed: file was not created." "ERROR"
        return $false
    }

    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8

        $required = @("<!DOCTYPE html>", "<html", "</html>")
        foreach ($token in $required) {
            if ($content -notmatch [regex]::Escape($token)) {
                Write-ToolLog "$ReportName validation failed: missing token $token." "ERROR"
                return $false
            }
        }

        if ($content -match "\uFFFD") {
            Write-ToolLog "$ReportName validation warning: replacement character detected. Check encoding/source text." "WARN"
        }

        Write-ToolLog "$ReportName validation passed: $Path" "SUCCESS"
        return $true
    }
    catch {
        Write-ToolLog "$ReportName validation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}



function Get-AnalystWorkflowState {
    $status = [ordered]@{}

    $checkboxMap = [ordered]@{
        UserContacted = "User contacted"
        PasswordResetRecommended = "Password reset recommended"
        SessionRevocationRecommended = "Session revocation recommended"
        DeviceIsolationRecommended = "Device isolation recommended"
        OAuthConsentReviewed = "OAuth consent reviewed"
        DlpReviewCompleted = "DLP review completed"
        EscalatedToIR = "Escalated to IR"
        FalsePositiveSuspected = "False positive suspected"
        MonitoringRecommended = "Monitoring recommended"
    }

    foreach ($key in $checkboxMap.Keys) {
        $ctrlName = "chkWF_$key"
        $checked = $false

        try {
            $ctrl = Get-Variable -Name $ctrlName -Scope Script -ErrorAction SilentlyContinue
            if ($ctrl -and $ctrl.Value) {
                $checked = [bool]$ctrl.Value.Checked
            }
        }
        catch {}

        $status[$checkboxMap[$key]] = if ($checked) { "Yes" } else { "No" }
    }

    $notes = ""
    $assessment = ""
    try { if ($Script:txtAnalystNotes) { $notes = $Script:txtAnalystNotes.Text.Trim() } } catch {}
    try { if ($Script:txtAnalystAssessment) { $assessment = $Script:txtAnalystAssessment.Text.Trim() } } catch {}

    $Script:AnalystNotes = $notes
    $Script:AnalystAssessment = $assessment
    $Script:AnalystStatus = $status

    return [ordered]@{
        Notes = $notes
        Assessment = $assessment
        Status = $status
    }
}

function Convert-AnalystWorkflowToHtml {
    $workflow = Get-AnalystWorkflowState

    $initialNotes = if ([string]::IsNullOrWhiteSpace($workflow.Notes)) { "" } else { ConvertTo-SafeHtml $workflow.Notes }
    $initialAssessment = if ([string]::IsNullOrWhiteSpace($workflow.Assessment)) { "" } else { ConvertTo-SafeHtml $workflow.Assessment }

    return @"
<div class="analyst-live-panel">
  <div class="analyst-live-header">
    <div>
      <h3>Analyst Workspace</h3>
      <p>Enter assessment, notes, and workflow status directly in this report. Use Generate Analyst Summary to save an UPDATED HTML copy with the notes embedded. The file saves to your browser Downloads folder unless your browser prompts for a location. Replace the prior UPDATED file when prompted.</p>
    </div>
    <div class="report-save-actions"><button class="report-save-button" onclick="generateAnalystSummary()" type="button">Generate Analyst Summary</button><small>Saves as an UPDATED HTML copy. Replace the prior UPDATED file when prompted.</small></div>
  </div>

  <label class="analyst-label" for="analystAssessment">Analyst Assessment</label>
  <textarea id="analystAssessment" class="analyst-textarea" placeholder="Summarize the analyst conclusion, confidence, and current interpretation...">$initialAssessment</textarea>

  <label class="analyst-label" for="analystNotes">Analyst Notes</label>
  <textarea id="analystNotes" class="analyst-textarea notes" placeholder="Add investigation notes, user confirmation, validation steps, pivots, or handoff context...">$initialNotes</textarea>

  <div class="workflow-check-grid">
    <label><input type="checkbox" data-workflow="User contacted"> User contacted</label>
    <label><input type="checkbox" data-workflow="Password reset recommended"> Password reset recommended</label>
    <label><input type="checkbox" data-workflow="Session revocation recommended"> Session revocation recommended</label>
    <label><input type="checkbox" data-workflow="Device isolation recommended"> Device isolation recommended</label>
    <label><input type="checkbox" data-workflow="OAuth consent reviewed"> OAuth consent reviewed</label>
    <label><input type="checkbox" data-workflow="DLP review completed"> DLP review completed</label>
    <label><input type="checkbox" data-workflow="Escalated to IR"> Escalated to IR</label>
    <label><input type="checkbox" data-workflow="False positive suspected"> False positive suspected</label>
    <label><input type="checkbox" data-workflow="Monitoring recommended"> Monitoring recommended</label>
  </div>

  <div id="embeddedAnalystSummary" class="embedded-analyst-summary">
    <h3>Embedded Analyst Summary</h3>
    <p>This section updates live and is embedded into the UPDATED report copy.</p>
  </div>
</div>
"@
}

function Add-AnalystTimelineAnnotation {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    if (-not $Script:Investigation.AnalystTimeline) {
        $Script:Investigation.AnalystTimeline = @()
    }

    $Script:Investigation.AnalystTimeline += [pscustomobject]@{
        Timestamp = (Get-Date)
        Note = $Text
    }
}

function Convert-AnalystTimelineToHtml {
    if (-not $Script:Investigation -or -not $Script:Investigation.AnalystTimeline -or $Script:Investigation.AnalystTimeline.Count -eq 0) {
        return "<div class='report-card'><span class='status-tag tag-normal'>Normal</span>No analyst timeline annotations were added.</div>"
    }

    $items = foreach ($entry in $Script:Investigation.AnalystTimeline) {
        "<div class='timeline-note'><strong>$(ConvertTo-SafeHtml $entry.Timestamp)</strong><p>$(ConvertTo-SafeHtml $entry.Note)</p></div>"
    }

    return ($items -join "`n")
}

function Save-AnalystWorkflowToInvestigation {
    if (-not $Script:Investigation) { return }

    $workflow = Get-AnalystWorkflowState
    $Script:Investigation.AnalystNotes = $workflow.Notes
    $Script:Investigation.AnalystAssessment = $workflow.Assessment
    $Script:Investigation.AnalystStatus = $workflow.Status

    if (-not [string]::IsNullOrWhiteSpace($workflow.Notes)) {
        Add-UniqueInvestigationItem -Section "InvestigationPivots" -Value "Analyst notes were added to this investigation report."
    }

    if (-not [string]::IsNullOrWhiteSpace($workflow.Assessment)) {
        Add-UniqueInvestigationItem -Section "Recommendations" -Value "Review analyst assessment section for human validation and case context."
    }
}

function Clear-AnalystWorkflowInputs {
    try { if ($Script:txtAnalystNotes) { $Script:txtAnalystNotes.Clear() } } catch {}
    try { if ($Script:txtAnalystAssessment) { $Script:txtAnalystAssessment.Clear() } } catch {}

    foreach ($name in @(
        "chkWF_UserContacted",
        "chkWF_PasswordResetRecommended",
        "chkWF_SessionRevocationRecommended",
        "chkWF_DeviceIsolationRecommended",
        "chkWF_OAuthConsentReviewed",
        "chkWF_DlpReviewCompleted",
        "chkWF_EscalatedToIR",
        "chkWF_FalsePositiveSuspected",
        "chkWF_MonitoringRecommended"
    )) {
        try {
            $ctrl = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
            if ($ctrl -and $ctrl.Value) { $ctrl.Value.Checked = $false }
        }
        catch {}
    }

    $Script:AnalystNotes = ""
    $Script:AnalystAssessment = ""
    $Script:AnalystStatus = [ordered]@{}
    Write-ToolLog "Cleared analyst workflow notes and status selections." "INFO"
}



function Get-PotentialRemediationPlan {
    $evidence = ""
    try {
        if ($Script:Investigation) {
            $evidence = @(
                $Script:Investigation.IdentityRisk
                $Script:Investigation.Authentication
                $Script:Investigation.OAuthActivity
                $Script:Investigation.Alerts
                $Script:Investigation.Incidents
                $Script:Investigation.EndpointContext
                $Script:Investigation.EmailContext
                $Script:Investigation.UrlClickContext
                $Script:Investigation.CloudActivity
                $Script:Investigation.CloudAppEvents
                $Script:Investigation.PotentialGaps
                $Script:Investigation.ObservedRisks
                $Script:Investigation.Recommendations
                $Script:Investigation.InvestigationPivots
            ) -join " "
        }
    } catch {}

    $e = $evidence.ToLower()
    $plans = @()

    function New-RemediationGroup {
        param([string]$Area,[string]$Trigger,[string]$Why,[array]$Steps)
        [pscustomobject]@{ Area=$Area; Trigger=$Trigger; Why=$Why; Steps=$Steps }
    }

    if ($e -match "risk|signin|sign-in|mfa|conditional access|authentication|failed|interrupted|unmanaged|legacy") {
        $plans += New-RemediationGroup "Identity / Authentication" "Identity or authentication indicators" "Use these steps if suspicious sign-in, MFA, user risk, unmanaged device, or Conditional Access indicators are validated." @(
            "Validate sign-in activity with the user or business owner.",
            "Review MFA method, authentication strength, and recent MFA changes.",
            "Revoke active sessions if suspicious authentication is confirmed.",
            "Require password reset if credential compromise is suspected.",
            "Review Conditional Access coverage for unmanaged or non-compliant device access.",
            "Document whether the identity activity is confirmed suspicious, expected, or inconclusive."
        )
    }

    if ($e -match "email|url|phish|click|safelinks|sender|message|attachment|networkmessageid") {
        $plans += New-RemediationGroup "Email / URL Activity" "Email or URL indicators" "Use these steps if email delivery, URL click activity, phishing, or malicious message interaction is validated." @(
            "Identify all recipients and users who clicked the URL.",
            "Review Safe Links verdict, URL reputation, sender, subject, and delivery status.",
            "Purge delivered malicious messages if validated.",
            "Block sender, domain, URL, or attachment hash after confirmation.",
            "Pivot clickers into identity and endpoint review.",
            "Notify impacted users if business process requires user validation."
        )
    }

    if ($e -match "oauth|consent|app|application|permission|delegated|offline_access|mail.read|files.read") {
        $plans += New-RemediationGroup "OAuth / App Consent" "OAuth or app consent indicators" "Use these steps if suspicious app consent, high-interest permissions, or unexpected delegated access is found." @(
            "Review app publisher, app owner, consent source, and granted scopes.",
            "Validate business justification for the app and permissions.",
            "Remove risky delegated permissions if unauthorized.",
            "Disable, restrict, or block the app if suspicious.",
            "Review tenant app consent governance and admin consent workflow.",
            "Hunt for activity performed by the app or affected user after consent."
        )
    }

    if ($e -match "endpoint|device|process|powershell|script|logon|rdp|remoteinteractive|xdr|alert|incident") {
        $plans += New-RemediationGroup "Endpoint / XDR" "Endpoint or XDR indicators" "Use these steps if endpoint logons, process execution, remote access, XDR alerts, or suspicious device activity are validated." @(
            "Review device timeline in Defender XDR.",
            "Validate suspicious processes, command lines, network connections, and remote logons.",
            "Collect triage package if deeper endpoint validation is required.",
            "Isolate device only if suspicious execution or compromise is confirmed.",
            "Review related alerts/incidents and affected devices.",
            "Document containment decision and evidence supporting the action."
        )
    }

    if ($e -match "cloud|cloudapp|download|upload|share|anonymous|session|dlp|data movement|file") {
        $plans += New-RemediationGroup "Cloud Apps / Data Movement" "Cloud activity or data movement indicators" "Use these steps if post-authentication SaaS activity, file movement, sharing, unmanaged session access, or DLP visibility concerns are found." @(
            "Review cloud app activity after suspicious sign-in or URL click.",
            "Validate downloads, uploads, sharing, anonymous links, and unusual app access.",
            "Review DLP policy visibility and whether sensitive data was involved.",
            "Review Defender for Cloud Apps session controls and Conditional Access App Control coverage.",
            "Remove risky sharing links or permissions if unauthorized.",
            "Escalate to data owner or privacy/compliance team if sensitive data exposure is suspected."
        )
    }

    if ($plans.Count -eq 0) {
        $plans += New-RemediationGroup "General Validation" "No elevated category-specific indicators" "No strong category-specific remediation trigger was identified. Use these steps for analyst validation and documentation." @(
            "Review source health and confirm which telemetry was available.",
            "Validate findings with the user or business owner if needed.",
            "Use the playbook KQL side panel for manual pivots.",
            "Document whether the investigation is normal, inconclusive, or requires monitoring.",
            "Avoid remediation unless suspicious activity is validated."
        )
    }

    return $plans
}

function Convert-PotentialRemediationToHtml {
    $plans = Get-PotentialRemediationPlan
    $html = foreach ($plan in $plans) {
        $i = 0
        $steps = foreach ($step in $plan.Steps) {
            $i++
@"
<div class="remediation-step">
  <span>$i</span>
  <p>$(ConvertTo-SafeHtml $step)</p>
  <select data-remediation-status>
    <option>Recommended</option>
    <option>In Progress</option>
    <option>Completed</option>
    <option>Deferred</option>
    <option>Not Applicable</option>
  </select>
</div>
"@
        }

@"
<div class="remediation-card">
  <div class="remediation-card-head">
    <div>
      <h3>$(ConvertTo-SafeHtml $plan.Area)</h3>
      <p>$(ConvertTo-SafeHtml $plan.Why)</p>
    </div>
    <span class="status-tag tag-review">$(ConvertTo-SafeHtml $plan.Trigger)</span>
  </div>
  <div class="remediation-steps">$($steps -join "`n")</div>
</div>
"@
    }

@"
<div class="remediation-advisory">
  <strong>Advisory use only:</strong> These are potential remediation steps generated from investigation context. Validate findings before containment, account action, message purge, or control changes.
</div>
$($html -join "`n")
"@
}


function Convert-InvestigationWorkflowMaturityToHtml {
    $stages = @(
        [pscustomobject]@{ Stage="1. Identify"; Detail="Confirm the target user, investigation window, available telemetry, and initial concern." },
        [pscustomobject]@{ Stage="2. Validate"; Detail="Validate suspicious sign-ins, alerts, user activity, OAuth grants, email clicks, endpoint evidence, and source health." },
        [pscustomobject]@{ Stage="3. Pivot"; Detail="Use the strongest entities: user, device, IP address, URL/domain, message ID, OAuth app, and cloud activity." },
        [pscustomobject]@{ Stage="4. Assess Impact"; Detail="Determine affected users, devices, apps, sessions, files, messages, and defensive visibility gaps." },
        [pscustomobject]@{ Stage="5. Identify Gaps"; Detail="Identify missing controls such as unmanaged device access, missing session restrictions, limited DLP visibility, OAuth governance gaps, or unavailable telemetry." },
        [pscustomobject]@{ Stage="6. Recommend Actions"; Detail="Document advisory remediation, gap closure steps, escalation needs, monitoring requirements, and analyst disposition." }
    )

    $rows = foreach ($s in $stages) {
@"
<div class="workflow-stage-card">
  <span>$(ConvertTo-SafeHtml $s.Stage)</span>
  <p>$(ConvertTo-SafeHtml $s.Detail)</p>
</div>
"@
    }

    return @"
<div class="workflow-maturity-panel">
  <div class="workflow-maturity-intro">
    <strong>Investigation workflow:</strong> Identify -> Validate -> Pivot -> Assess Impact -> Identify Gaps -> Recommend Actions.
  </div>
  <div class="workflow-stage-grid">$($rows -join "`n")</div>
</div>
"@
}

function Convert-InvestigationDispositionToHtml {
    return @"
<div class="disposition-panel">
  <div class="disposition-header">
    <h3>Investigation Disposition</h3>
    <p>Use this section in the report to mark the analyst outcome. This is analyst-owned and does not perform remediation.</p>
  </div>
  <div class="disposition-grid">
    <label><input type="radio" name="investigationDisposition" data-disposition value="Open"> Open</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="Investigating"> Investigating</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="Escalated to IR"> Escalated to IR</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="Monitoring Required"> Monitoring Required</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="Resolved - Benign"> Resolved - Benign</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="Resolved - Confirmed Incident"> Resolved - Confirmed Incident</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="False Positive"> False Positive</label>
    <label><input type="radio" name="investigationDisposition" data-disposition value="Inconclusive"> Inconclusive</label>
  </div>
  <label class="analyst-label" for="dispositionRationale">Disposition Rationale</label>
  <textarea id="dispositionRationale" class="analyst-textarea notes" placeholder="Explain why the investigation is open, resolved, escalated, benign, confirmed, inconclusive, or requires monitoring..."></textarea>
</div>
"@
}

function Convert-PerSectionAnalystNotesToHtml {
    $sections = @(
        "Authentication & Identity",
        "Email & URL Activity",
        "Email Attack / Campaign Hunting",
        "Endpoint / XDR",
        "Cloud Apps & Session Activity",
        "OAuth / App Consent",
        "Cross-Layer Correlation",
        "Defensive Gaps",
        "Remediation Review"
    )

    $cards = foreach ($section in $sections) {
        $id = ($section -replace '[^a-zA-Z0-9]', '')
@"
<div class="section-note-card">
  <h3>$(ConvertTo-SafeHtml $section)</h3>
  <textarea id="sectionNote_$id" data-section-note="$(ConvertTo-SafeHtml $section)" class="analyst-textarea" placeholder="Add analyst notes, validation details, evidence interpretation, or handoff notes for this area..."></textarea>
</div>
"@
    }

    return @"
<div class="section-notes-grid">
$($cards -join "`n")
</div>
"@
}

function Convert-InvestigationTimelineCorrelationToHtml {
    $events = @()

    function Add-TimelineEvent {
        param([string]$Source,[string]$Detail,[string]$Level="Review")
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $script:events += [pscustomobject]@{
                Source = $Source
                Detail = $Detail
                Level = $Level
            }
        }
    }

    try {
        foreach ($item in @($Script:Investigation.Authentication | Select-Object -First 6)) {
            Add-TimelineEvent -Source "Authentication" -Detail ([string]$item) -Level "Review"
        }
        foreach ($item in @($Script:Investigation.UrlClickContext | Select-Object -First 4)) {
            Add-TimelineEvent -Source "Email / URL" -Detail ([string]$item) -Level "Investigate"
        }
        foreach ($item in @($Script:Investigation.OAuthActivity | Select-Object -First 4)) {
            Add-TimelineEvent -Source "OAuth" -Detail ([string]$item) -Level "Review"
        }
        foreach ($item in @($Script:Investigation.EndpointContext | Select-Object -First 4)) {
            Add-TimelineEvent -Source "Endpoint" -Detail ([string]$item) -Level "Review"
        }
        foreach ($item in @($Script:Investigation.CloudAppEvents | Select-Object -First 4)) {
            Add-TimelineEvent -Source "Cloud Apps" -Detail ([string]$item) -Level "Review"
        }
    } catch {}

    if ($events.Count -eq 0) {
        return "<div class='report-card'><span class='status-tag tag-normal'>Timeline</span>No timeline correlation events were available from the collected investigation context. Use playbook KQL pivots if deeper chronology is required.</div>"
    }

    $i = 0
    $html = foreach ($event in $events) {
        $i++
        $tagClass = if ($event.Level -eq "Investigate") { "tag-investigate" } else { "tag-review" }
@"
<div class="timeline-correlation-item">
  <div class="timeline-index">$i</div>
  <div>
    <span class="status-tag $tagClass">$(ConvertTo-SafeHtml $event.Source)</span>
    <p>$(ConvertTo-SafeHtml $event.Detail)</p>
  </div>
</div>
"@
    }

    return @"
<div class="timeline-correlation-panel">
  <div class="timeline-correlation-help">Use this as a starting storyline. Validate timestamps and source telemetry before drawing conclusions.</div>
  $($html -join "`n")
</div>
"@
}

function Convert-GapClosureGuidanceToHtml {
    $evidence = ""
    try {
        $evidence = @(
            $Script:Investigation.PotentialGaps
            $Script:Investigation.Recommendations
            $Script:Investigation.SourceHealth
            $Script:Investigation.CloudActivity
            $Script:Investigation.OAuthActivity
            $Script:Investigation.Authentication
            $Script:Investigation.DlpVisibility
        ) -join " "
    } catch {}

    $e = $evidence.ToLower()
    $gaps = @()

    function New-GapClosure {
        param([string]$Gap,[string]$Why,[array]$Steps)
        [pscustomobject]@{ Gap=$Gap; Why=$Why; Steps=$Steps }
    }

    if ($e -match "unmanaged|non-compliant|device trust|conditional access") {
        $gaps += New-GapClosure "Unmanaged or non-compliant device access" "Unmanaged access can reduce confidence in session integrity and endpoint control." @(
            "Review Conditional Access policy coverage for the target user and cloud apps.",
            "Require compliant device, hybrid joined device, or approved app where appropriate.",
            "Apply session controls for unmanaged access to sensitive SaaS apps.",
            "Validate exclusions, break-glass accounts, and pilot groups before enforcement."
        )
    }

    if ($e -match "session|conditional access app control|cloud app control|mdca") {
        $gaps += New-GapClosure "Limited session control visibility" "Risky sessions may not be restricted or monitored if session control policies are incomplete." @(
            "Review Defender for Cloud Apps Conditional Access App Control coverage.",
            "Confirm target applications are onboarded for session monitoring/control.",
            "Apply monitor-only or block download policies for unmanaged sessions where appropriate.",
            "Validate policy impact with test users before broad enforcement."
        )
    }

    if ($e -match "dlp|data movement|download|share|sensitive") {
        $gaps += New-GapClosure "DLP or data movement visibility gap" "Large downloads, sharing, or sensitive data movement may require DLP and data owner validation." @(
            "Review Purview DLP policy coverage for the affected workloads.",
            "Validate whether sensitive information types or sensitivity labels are present.",
            "Review sharing links, external recipients, and anonymous access.",
            "Escalate to data owner/privacy team if sensitive exposure is suspected."
        )
    }

    if ($e -match "oauth|consent|app governance|delegated|permission") {
        $gaps += New-GapClosure "OAuth governance gap" "Unreviewed OAuth grants can provide persistent access after user authentication risk." @(
            "Review user and admin consent settings.",
            "Require admin consent workflow for high-risk permissions.",
            "Review publisher verification and app governance alerts.",
            "Remove unauthorized grants and monitor for re-consent attempts."
        )
    }

    if ($e -match "telemetry unavailable|source health|schema|table|advanced hunting|not available") {
        $gaps += New-GapClosure "Telemetry availability gap" "Missing tables or limited telemetry reduce investigation confidence." @(
            "Review licensing, service onboarding, role access, and data retention.",
            "Validate Advanced Hunting tables manually for required workloads.",
            "Document unavailable sources in the case notes.",
            "Do not treat missing telemetry as proof of no suspicious activity."
        )
    }

    if ($gaps.Count -eq 0) {
        $gaps += New-GapClosure "No specific defensive gap closure triggered" "No strong control gap signal was detected from this report context." @(
            "Review Source Health to confirm telemetry completeness.",
            "Review Potential Remediation Steps if suspicious activity is validated.",
            "Document any manually observed gaps in the analyst notes."
        )
    }

    $html = foreach ($gap in $gaps) {
        $i = 0
        $steps = foreach ($step in $gap.Steps) {
            $i++
            "<li><span>$i</span><p>$(ConvertTo-SafeHtml $step)</p></li>"
        }

@"
<div class="gap-closure-card">
  <h3>$(ConvertTo-SafeHtml $gap.Gap)</h3>
  <p>$(ConvertTo-SafeHtml $gap.Why)</p>
  <ol>$($steps -join "`n")</ol>
</div>
"@
    }

    return ($html -join "`n")
}

function Convert-KqlExecutionValidationToHtml {
    $kqlRoot = $Script:KqlPath
    $items = @()

    if ($kqlRoot -and (Test-Path $kqlRoot)) {
        $files = @(Get-ChildItem -Path $kqlRoot -Filter "*.kql" -Recurse -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $relative = $file.FullName.Replace($kqlRoot, "").TrimStart("\","/")
            $status = "Template Ready"
            $detail = "KQL file is available for playbook rendering."

            if ($content -match "\{TargetUser\}" -or $content -match "\{LookbackDays\}" -or $content -match "\{TargetAccount\}" -or $content -match "\{TargetDomain\}") {
                $detail = "Uses Shadow Trace Ops template placeholders."
            }

            if ($content -match "AADSignInEventsBeta") {
                $status = "Review"
                $detail = "Uses AADSignInEventsBeta. Prefer EntraIdSignInEvents where available."
            }

            if ($content -match "column_ifexists") {
                $detail += " Schema-safe column handling detected."
            }

            $items += [pscustomobject]@{
                File = $relative
                Status = $status
                Detail = $detail
            }
        }
    }

    if ($items.Count -eq 0) {
        return "<div class='report-card'><span class='status-tag tag-review'>KQL</span>No KQL files were found under Toolkit\Config\KQL.</div>"
    }

    $rows = foreach ($item in ($items | Sort-Object File)) {
        $tag = if ($item.Status -eq "Review") { "tag-review" } else { "tag-normal" }
@"
<tr>
  <td>$(ConvertTo-SafeHtml $item.File)</td>
  <td><span class="status-tag $tag">$(ConvertTo-SafeHtml $item.Status)</span></td>
  <td>$(ConvertTo-SafeHtml $item.Detail)</td>
</tr>
"@
    }

    return @"
<div class="kql-validation-panel">
  <p>KQL validation here is static/template validation. Runtime Advanced Hunting success still depends on tenant licensing, RBAC, schema, and data availability.</p>
  <table>
    <tr><th>KQL File</th><th>Status</th><th>Validation Notes</th></tr>
    $($rows -join "`n")
  </table>
</div>
"@
}

function Export-PrimaryDashboardReport {
    
    if (-not (Test-CanExportShadowTraceReport)) { return $null }
try {
        Save-AnalystWorkflowToInvestigation
        if (-not $Script:Investigation) {
            [System.Windows.Forms.MessageBox]::Show("No investigation data exists yet. Run an investigation first.","No Investigation Data","OK","Warning") | Out-Null
            return $null
        }

        $upn = $Script:Investigation.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($upn)) { $upn = "UnknownUser" }

        $safeName = $upn.Replace("@","_").Replace(".","_").Replace("\","_").Replace("/","_")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $reportFile = Join-Path $Script:ReportPath "ShadowTraceOps-PrimaryDashboard-$safeName-$timestamp.html"

        $logoHtml = Get-LogoHtml

        $identityCount = if ($Script:Investigation.IdentityRisk) { $Script:Investigation.IdentityRisk.Count } else { 0 }
        $authCount = if ($Script:Investigation.Authentication) { $Script:Investigation.Authentication.Count } else { 0 }
        $emailUrlCount = @($Script:Investigation.EmailContext + $Script:Investigation.UrlClickContext).Count
        $endpointXdrCount = @($Script:Investigation.EndpointContext + $Script:Investigation.Alerts + $Script:Investigation.Incidents).Count
        $cloudCount = @($Script:Investigation.CloudActivity + $Script:Investigation.CloudAppEvents).Count
        $oauthCount = if ($Script:Investigation.OAuthActivity) { $Script:Investigation.OAuthActivity.Count } else { 0 }
        $gapCount = if ($Script:Investigation.PotentialGaps) { $Script:Investigation.PotentialGaps.Count } else { 0 }

        $concernRows = @(
            [pscustomobject]@{Name="Identity Risk"; Count=$identityCount; Color="#2f80ed"; Anchor="identity-risk"},
            [pscustomobject]@{Name="Authentication"; Count=$authCount; Color="#f2994a"; Anchor="authentication"},
            [pscustomobject]@{Name="Email / URL"; Count=$emailUrlCount; Color="#eb5757"; Anchor="email-url"},
            [pscustomobject]@{Name="Endpoint / XDR"; Count=$endpointXdrCount; Color="#27ae60"; Anchor="endpoint-xdr"},
            [pscustomobject]@{Name="Cloud Activity"; Count=$cloudCount; Color="#9b51e0"; Anchor="cloud-activity"},
            [pscustomobject]@{Name="OAuth / App Access"; Count=$oauthCount; Color="#00bcd4"; Anchor="oauth"},
            [pscustomobject]@{Name="Gaps & Exposures"; Count=$gapCount; Color="#f2c94c"; Anchor="gaps"}
        )

        $activeRows = @($concernRows | Where-Object { $_.Count -gt 0 })
        if ($activeRows.Count -eq 0) {
            $activeRows = @([pscustomobject]@{Name="No Elevated Signals"; Count=1; Color="#27ae60"; Anchor="summary"})
        }

        $total = ($activeRows | Measure-Object -Property Count -Sum).Sum
        if (-not $total -or $total -lt 1) { $total = 1 }

        $start = 0
        $segments = @()
        $legend = @()
        foreach ($row in $activeRows) {
            $pct = [math]::Round(($row.Count / $total) * 100, 1)
            $end = $start + $pct
            $segments += "$($row.Color) $start% $end%"
            $legend += "<a class='legend-row' href='#$($row.Anchor)'><span class='legend-dot' style='background:$($row.Color)'></span><span>$(ConvertTo-SafeHtml $row.Name)</span><strong>$pct%</strong><small>($($row.Count))</small></a>"
            $start = $end
        }

        $sorted = @($activeRows | Sort-Object Count -Descending)
        $top = $sorted[0]
        $second = if ($sorted.Count -gt 1) { $sorted[1] } else { $sorted[0] }

        if (Get-Command Invoke-InvestigationScoring -ErrorAction SilentlyContinue) {
            Invoke-InvestigationScoring
        }

        $scoreContributors = @()
        $calculatedScore = 0

        if ($identityCount -gt 0) {
            $calculatedScore += 2
            $scoreContributors += "+2 Identity risk indicators detected"
        }
        if ($authCount -gt 0) {
            $authText = ($Script:Investigation.Authentication -join " ").ToLower()
            if ($authText -match "failed|interrupted|risk|unknown|unmanaged") {
                $calculatedScore += 2
                $scoreContributors += "+2 Authentication risk, failure, or unmanaged-device indicators"
            }
            else {
                $calculatedScore += 1
                $scoreContributors += "+1 Authentication activity reviewed"
            }
        }
        if ($oauthCount -gt 0) {
            $oauthText = ($Script:Investigation.OAuthActivity -join " ").ToLower()
            if ($oauthText -match "offline_access|files.readwrite|mail.readwrite|consent|delegated|scope") {
                $calculatedScore += 2
                $scoreContributors += "+2 OAuth or app permission review indicators"
            }
            else {
                $calculatedScore += 1
                $scoreContributors += "+1 OAuth activity present"
            }
        }
        if ($endpointXdrCount -gt 0) {
            $calculatedScore += 2
            $scoreContributors += "+2 Endpoint or XDR evidence present"
        }
        if ($emailUrlCount -gt 0) {
            $calculatedScore += 1
            $scoreContributors += "+1 Email or URL context present"
        }
        if ($cloudCount -gt 0) {
            $calculatedScore += 1
            $scoreContributors += "+1 Cloud activity context present"
        }
        if ($gapCount -gt 0) {
            $calculatedScore += 1
            $scoreContributors += "+1 Potential control or visibility gaps identified"
        }

        if ($scoreContributors.Count -eq 0) {
            $scoreContributors += "+0 No elevated weighted indicators identified"
        }

        $score = $calculatedScore
        $classification = if ($score -ge 9) { "Critical" } elseif ($score -ge 6) { "High" } elseif ($score -ge 3) { "Medium" } else { "Low" }

        $sourceHealthText = ($Script:Investigation.SourceHealth -join " ").ToLower()
        if ($score -ge 3 -and $sourceHealthText -notmatch "failed|permission|schema|unavailable") {
            $confidence = "Moderate"
        }
        elseif ($score -ge 6 -and $sourceHealthText -notmatch "failed|permission|schema|unavailable") {
            $confidence = "High"
        }
        elseif ($score -eq 0) {
            $confidence = "Low"
        }
        else {
            $confidence = "Needs Validation"
        }

        $Script:Investigation.InvestigationScore = $score
        $Script:Investigation.ScoreClassification = $classification
        $Script:Investigation.ConfidenceLevel = $confidence
        $Script:Investigation.ScoreBreakdown = $scoreContributors

        $scoreContributorHtml = foreach ($contributor in $scoreContributors | Select-Object -First 4) {
            "<div class=""score-reason"">$(ConvertTo-SafeHtml $contributor)</div>"
        }
        $scoreContributorHtml = $scoreContributorHtml -join "`n"

        $scoreNeedleLeft = [Math]::Min(100, [Math]::Round(($score / 10) * 100, 0))

        $scoreClassCss = switch ($classification) {
            "Critical" { "score-critical" }
            "High" { "score-high" }
            "Medium" { "score-medium" }
            default { "score-low" }
        }

        $scoreMeaning = switch ($classification) {
            "Critical" { "High signal density. Multiple correlated indicators or control gaps exist, but this is still advisory until validated." }
            "High" { "Elevated signal severity. Prompt investigation is recommended to validate scope and impact." }
            "Medium" { "Meaningful signals exist. Analyst review is recommended, but immediate escalation may depend on validation." }
            default { "Low signal severity. Routine review unless additional evidence changes context." }
        }

        $priorityMeaning = "Priority is the recommended analyst handling level. It considers severity, confidence, telemetry completeness, and whether evidence is validated. It may be lower than the score when the report needs analyst validation before escalation."

        $summaryTable = ConvertTo-HtmlTableFromHashtable $Script:Investigation.UserSummary
        $findings = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.ObservedRisks + $Script:Investigation.PotentialGaps + $Script:Investigation.InvestigationPivots) -MaxItems 6 -EmptyMessage "No elevated findings were generated."
        $recommendations = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Recommendations -MaxItems 5 -EmptyMessage "No recommendations were generated."
        $identityCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.IdentityRisk -MaxItems 8 -EmptyMessage "No identity risk findings were collected."
        $authCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Authentication -MaxItems 8 -EmptyMessage "No authentication records were collected."
        $emailCards = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.EmailContext + $Script:Investigation.UrlClickContext) -MaxItems 8 -EmptyMessage "No email or URL records were collected."
        $xdrCards = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.EndpointContext + $Script:Investigation.Alerts + $Script:Investigation.Incidents) -MaxItems 8 -EmptyMessage "No endpoint or XDR records were collected."
        $cloudCards = ConvertTo-ReportCardsHtml -Items ($Script:Investigation.CloudActivity + $Script:Investigation.CloudAppEvents) -MaxItems 8 -EmptyMessage "No cloud activity records were collected."
        $oauthCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.OAuthActivity -MaxItems 8 -EmptyMessage "No OAuth records were collected."
        $gapCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.PotentialGaps -MaxItems 8 -EmptyMessage "No potential gaps were identified."
        $sourceCards = ConvertTo-ReportCardsHtml -Items $Script:Investigation.SourceHealth -MaxItems 8 -EmptyMessage "No source health records were captured."
        $playbookHtml = Get-PlaybookSidePanelHtml
        $kqlParameterSummaryHtml = Get-KqlParameterSummaryHtml
        Save-AnalystWorkflowToInvestigation
        $analystWorkflowHtml = Convert-AnalystWorkflowToHtml
        $analystTimelineHtml = Convert-AnalystTimelineToHtml

        $priorityHtml = @"
<div class='priority-row'>
  <a class='priority-card first' href='#$($top.Anchor)'><span>Start Here</span><strong>$(ConvertTo-SafeHtml $top.Name)</strong><small>$($top.Count) signal(s)</small></a>
  <a class='priority-card second' href='#$($second.Anchor)'><span>Second Pivot</span><strong>$(ConvertTo-SafeHtml $second.Name)</strong><small>$($second.Count) signal(s)</small></a>
</div>
"@

        $moduleNav = foreach ($row in $concernRows) {
            $class = if ($row.Count -gt 0) { "review" } else { "normal" }
            "<a class='module-link $class' href='#$($row.Anchor)'><span>$(ConvertTo-SafeHtml $row.Name)</span><strong>$($row.Count)</strong></a>"
        }

        $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Shadow Trace Ops Primary Dashboard</title>
<style>
html { scroll-behavior:smooth; }
body {
  margin:0;
  padding:22px;
  font-family:Segoe UI, Arial, sans-serif;
  color:#f5f1ff;
  background: radial-gradient(circle at 18% 0%, rgba(111,54,160,.35), transparent 32%), radial-gradient(circle at 90% 5%, rgba(66,29,100,.35), transparent 30%), #07080f;
}
.shell { max-width:1600px; margin:0 auto; }
.hero, .panel, .card, details {
  background:linear-gradient(180deg, rgba(20,22,34,.97), rgba(8,10,18,.98));
  border:1px solid #56336f;
  border-radius:18px;
  box-shadow:0 0 30px rgba(0,0,0,.30);
}
.hero {
  display:grid;
  grid-template-columns:1fr 190px;
  gap:20px;
  padding:24px 28px;
  border-left:6px solid #b26cff;
}
h1 { margin:0; font-size:42px; letter-spacing:.5px; }
.ops { color:#b26cff; }
.subtitle { color:#d7c4ef; margin-top:6px; }
.logo-area { display:flex; justify-content:flex-end; align-items:center; }
.tool-logo { max-width:135px; max-height:135px; filter:drop-shadow(0 0 18px rgba(178,108,255,.45)); }
.tenant-logo-placeholder, .tenant-logo { display:none; }
.meta { display:grid; grid-template-columns:repeat(4,1fr); gap:10px; margin-top:18px; }
.meta div { background:rgba(255,255,255,.035); border:1px solid #3b284d; border-radius:12px; padding:10px; }
.meta span { display:block; color:#b26cff; font-weight:800; font-size:12px; margin-bottom:4px; }
.layout { display:grid; grid-template-columns:260px 1fr 335px; gap:18px; margin-top:18px; align-items:start; }
.left, .right { position:sticky; top:18px; display:grid; gap:12px; }
.panel, .card { padding:16px; }
.panel h2, .card h2, details summary { color:#c27cff; text-transform:uppercase; letter-spacing:.3px; font-size:18px; margin:0 0 12px 0; }
.module-link { display:flex; justify-content:space-between; align-items:center; color:#fff; text-decoration:none; background:rgba(255,255,255,.035); border:1px solid #3b284d; border-radius:12px; padding:12px; margin:8px 0; }
.module-link:hover { border-color:#b26cff; background:rgba(178,108,255,.12); }
.module-link strong { background:#231631; border:1px solid #56336f; border-radius:999px; padding:3px 8px; }
.module-link.normal { border-color:rgba(46,204,113,.35); }
.module-link.review { border-color:rgba(241,196,15,.35); }
.metrics { display:grid; grid-template-columns:repeat(6,1fr); gap:12px; margin-bottom:18px; }
.metric { background:linear-gradient(180deg, rgba(54,27,76,.65), rgba(10,12,20,.92)); border:1px solid #56336f; border-radius:16px; padding:18px 10px; text-align:center; }
.metric .icon { color:#b26cff; font-size:12px; font-weight:900; margin-bottom:8px; }
.metric .num { font-size:32px; font-weight:900; }
.metric .label { color:#d7c4ef; font-size:12px; margin-top:4px; }
.main-two { display:grid; grid-template-columns:1.15fr .85fr; gap:18px; }
.donut-wrap { display:grid; grid-template-columns:245px 1fr; gap:16px; align-items:center; }
.donut { width:230px; height:230px; border-radius:50%; display:grid; place-items:center; box-shadow:inset 0 0 16px rgba(0,0,0,.50), 0 0 24px rgba(178,108,255,.18); }
.hole { width:108px; height:108px; border-radius:50%; background:#080911; border:1px solid #3b284d; display:flex; flex-direction:column; align-items:center; justify-content:center; }
.hole strong { font-size:31px; }
.hole span { color:#d7c4ef; font-size:12px; text-align:center; }
.legend { display:grid; gap:8px; }
.legend-row { display:grid; grid-template-columns:14px 1fr 55px 50px; gap:8px; align-items:center; color:#fff; text-decoration:none; border-bottom:1px solid rgba(255,255,255,.08); padding-bottom:8px; }
.legend-dot { width:12px; height:12px; border-radius:3px; }
.priority-row { display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-top:14px; }
.priority-card { color:#fff; text-decoration:none; border-radius:14px; padding:14px; background:rgba(255,255,255,.035); border:1px solid #3b284d; }
.priority-card.first { border-color:#2f80ed; }
.priority-card.second { border-color:#f2994a; }
.priority-card span { display:block; color:#d7c4ef; font-size:12px; text-transform:uppercase; font-weight:800; }
.priority-card strong { display:block; margin-top:4px; }
.score-grid { display:grid; grid-template-columns:repeat(3,1fr); gap:10px; }
.score-box { border:1px solid #3b284d; border-radius:12px; padding:12px; text-align:center; background:rgba(255,255,255,.035); }
.score-box strong { display:block; font-size:25px; }
.score-box span { color:#d7c4ef; font-size:12px; }
details { margin-bottom:14px; overflow:hidden; }
details summary { cursor:pointer; list-style:none; padding:16px 18px; margin:0; }
details summary::-webkit-details-marker { display:none; }
.detail-body { padding:0 18px 18px 18px; }
.report-card { border:1px solid #3b284d; border-left:4px solid #8a57c2; border-radius:12px; padding:12px; margin-bottom:10px; background:rgba(255,255,255,.035); line-height:1.45; overflow-wrap:anywhere; }
.status-tag { display:inline-block; padding:3px 7px; margin-right:7px; border-radius:999px; font-size:10px; font-weight:900; text-transform:uppercase; }
.tag-normal { background:rgba(46,204,113,.15); color:#6ee7a0; border:1px solid rgba(46,204,113,.4); }
.tag-review { background:rgba(241,196,15,.15); color:#ffd86b; border:1px solid rgba(241,196,15,.4); }
.tag-investigate { background:rgba(255,92,92,.15); color:#ff8d8d; border:1px solid rgba(255,92,92,.4); }
.tag-validate { background:rgba(178,108,255,.15); color:#d4a8ff; border:1px solid rgba(178,108,255,.4); }
table { width:100%; border-collapse:collapse; }
th,td { border:1px solid #3b284d; padding:9px; text-align:left; overflow-wrap:anywhere; word-break:normal; }
th { color:#c27cff; background:rgba(255,255,255,.04); width:220px; }
.actions a { display:block; text-decoration:none; color:#fff; border:1px solid #3b284d; background:rgba(255,255,255,.035); border-radius:12px; padding:11px; margin:8px 0; }
.actions a:hover { border-color:#b26cff; color:#d4a8ff; }
.footer { margin-top:18px; color:#bdb2d0; border-top:1px solid #3b284d; padding-top:14px; display:flex; justify-content:space-between; }

.report-summary-panel {
  overflow: hidden;
}
.summary-kv {
  border:1px solid #3b284d;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:10px;
}
.summary-kv span {
  display:block;
  color:#c27cff;
  font-size:12px;
  font-weight:800;
  text-transform:uppercase;
  letter-spacing:.3px;
  margin-bottom:4px;
}
.summary-kv strong {
  display:block;
  color:#fff;
  font-size:13px;
  line-height:1.35;
  font-weight:600;
  overflow-wrap:anywhere;
  word-break:normal;
}
.right {
  min-width:0;
}
.right .panel {
  min-width:0;
  overflow:hidden;
}


.playbook-grid { display:grid; grid-template-columns:repeat(2,1fr); gap:12px; }
.playbook-card {
  border:1px solid #3b284d;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:12px;
  margin-bottom:10px;
}
.playbook-card div { display:flex; justify-content:space-between; gap:10px; align-items:center; }
.playbook-card strong { color:#fff; }
.playbook-card span {
  color:#ffd86b;
  border:1px solid rgba(241,196,15,.4);
  background:rgba(241,196,15,.12);
  border-radius:999px;
  padding:3px 8px;
  font-size:11px;
  font-weight:800;
}
.playbook-card p { color:#d7c4ef; line-height:1.45; margin:8px 0; }
.playbook-card small { color:#bdb2d0; }


.score-card-panel {
  min-height: 360px;
}
.risk-meter {
  position: relative;
  display: grid;
  grid-template-columns: 1fr 1fr 1fr 1fr;
  gap: 4px;
  margin-top: 16px;
  padding-bottom: 18px;
}
.risk-band {
  height: 58px;
  border-radius: 10px;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  border: 1px solid rgba(255,255,255,.12);
  font-weight: 900;
}
.risk-band span {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: .4px;
}
.risk-band small {
  margin-top: 3px;
  color: rgba(255,255,255,.78);
}
.risk-band.low { background: rgba(46,204,113,.16); color: #6ee7a0; }
.risk-band.medium { background: rgba(241,196,15,.16); color: #ffd86b; }
.risk-band.high { background: rgba(255,152,67,.16); color: #ffb86b; }
.risk-band.critical { background: rgba(255,92,92,.16); color: #ff8d8d; }
.risk-needle {
  position: absolute;
  bottom: 3px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #ffffff;
  border: 2px solid #b26cff;
  box-shadow: 0 0 14px rgba(178,108,255,.75);
  transform: translateX(-50%);
}
.risk-definitions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin-top: 8px;
}
.risk-definitions div {
  border: 1px solid #3b284d;
  border-radius: 10px;
  background: rgba(255,255,255,.035);
  padding: 8px;
  font-size: 12px;
  color: #d7c4ef;
  line-height: 1.35;
}
.risk-definitions strong {
  color: #ffffff;
}
.score-reasons {
  margin-top: 12px;
}
.score-reasons h3 {
  color: #c27cff;
  font-size: 13px;
  margin: 0 0 8px 0;
  text-transform: uppercase;
  letter-spacing: .3px;
}
.score-reason {
  border-left: 3px solid #b26cff;
  background: rgba(255,255,255,.035);
  border-radius: 8px;
  padding: 7px 9px;
  margin-bottom: 6px;
  font-size: 12px;
  color: #f4f1ff;
}


.score-priority-explainer {
  margin-top: 12px;
  display: grid;
  gap: 10px;
}
.explainer-card {
  border:1px solid #3b284d;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:11px 12px;
}
.explainer-card span {
  display:block;
  color:#c27cff;
  font-size:12px;
  font-weight:900;
  text-transform:uppercase;
  letter-spacing:.35px;
  margin-bottom:5px;
}
.explainer-card strong {
  display:block;
  color:#fff;
  font-size:13px;
  margin-bottom:4px;
}
.explainer-card small {
  color:#d7c4ef;
  line-height:1.35;
  display:block;
}
.explainer-card.score-critical {
  border-left:4px solid #ff5c5c;
}
.explainer-card.score-high {
  border-left:4px solid #ffb86b;
}
.explainer-card.score-medium {
  border-left:4px solid #ffd86b;
}
.explainer-card.score-low {
  border-left:4px solid #6ee7a0;
}
.explainer-card.priority-card-note {
  border-left:4px solid #b26cff;
}


.playbook-card-grid {
  display:grid;
  grid-template-columns:repeat(2, minmax(0, 1fr));
  gap:12px;
}
.playbook-open-card {
  text-align:left;
  border:1px solid #3b284d;
  border-left:4px solid #b26cff;
  border-radius:14px;
  background:rgba(255,255,255,.04);
  color:#fff;
  padding:13px 14px;
  cursor:pointer;
  font-family:inherit;
  transition: all .15s ease;
}
.playbook-open-card:hover {
  transform: translateY(-1px);
  border-color:#b26cff;
  background:rgba(178,108,255,.12);
  box-shadow:0 0 18px rgba(178,108,255,.16);
}
.playbook-open-card .pb-title {
  display:block;
  font-weight:900;
  color:#fff;
  margin-bottom:6px;
}
.playbook-open-card .pb-meta {
  display:inline-block;
  color:#ffd86b;
  border:1px solid rgba(241,196,15,.4);
  background:rgba(241,196,15,.12);
  border-radius:999px;
  padding:3px 8px;
  font-size:11px;
  font-weight:900;
  margin-bottom:7px;
}
.playbook-open-card small {
  display:block;
  color:#d7c4ef;
  line-height:1.35;
}
.playbook-data-store { display:none; }
.playbook-overlay {
  position:fixed;
  inset:0;
  background:rgba(0,0,0,.52);
  opacity:0;
  pointer-events:none;
  transition:opacity .18s ease;
  z-index:9998;
}
.playbook-overlay.open {
  opacity:1;
  pointer-events:auto;
}
.playbook-drawer {
  position:fixed;
  top:0;
  right:-520px;
  width:500px;
  max-width:92vw;
  height:100vh;
  background:linear-gradient(180deg,#17131f,#080911);
  border-left:1px solid #56336f;
  box-shadow:-18px 0 38px rgba(0,0,0,.38);
  z-index:9999;
  transition:right .2s ease;
  padding:22px;
  overflow-y:auto;
  box-sizing:border-box;
}
.playbook-drawer.open { right:0; }
.drawer-close {
  float:right;
  border:1px solid #56336f;
  background:#281536;
  color:#fff;
  border-radius:999px;
  padding:7px 12px;
  cursor:pointer;
}
.drawer-header {
  margin-top:28px;
  border-bottom:1px solid #3b284d;
  padding-bottom:16px;
}
.drawer-severity {
  display:inline-block;
  color:#ffd86b;
  border:1px solid rgba(241,196,15,.4);
  background:rgba(241,196,15,.12);
  border-radius:999px;
  padding:4px 10px;
  font-size:12px;
  font-weight:900;
  text-transform:uppercase;
}
.drawer-header h2 {
  color:#fff;
  margin:12px 0 4px 0;
  font-size:24px;
}
.drawer-header p {
  color:#bdb2d0;
  margin:0;
}
.drawer-section {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  margin-top:14px;
  padding:14px;
}
.drawer-section h4 {
  margin:0 0 8px 0;
  color:#c27cff;
  text-transform:uppercase;
  font-size:13px;
  letter-spacing:.3px;
}
.drawer-section p {
  color:#f4f1ff;
  line-height:1.5;
}
.drawer-steps {
  list-style:none;
  padding:0;
  margin:0;
  display:grid;
  gap:10px;
}
.drawer-steps li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
  align-items:start;
}
.drawer-steps li span {
  width:26px;
  height:26px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.drawer-steps li p {
  margin:2px 0 0 0;
  color:#f4f1ff;
  line-height:1.45;
}
.drawer-section pre {
  white-space:pre-wrap;
  word-break:break-word;
  background:#06070d;
  border:1px solid #3b284d;
  border-radius:12px;
  padding:12px;
  color:#e8ddff;
  font-size:12px;
}
.drawer-muted { color:#bdb2d0; }
.playbook-empty {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:12px;
  background:rgba(255,255,255,.035);
}

.kql-block { margin-top:10px; }
.kql-title { color:#ffd86b; font-weight:900; margin:8px 0 6px 0; font-size:12px; }
.kql-block pre { white-space:pre-wrap; word-break:break-word; background:#06070d; border:1px solid #3b284d; border-radius:12px; padding:12px; color:#e8ddff; font-size:12px; }


.analyst-workflow-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:14px;
  margin-bottom:12px;
}
.analyst-workflow-card h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:14px;
  margin:0 0 8px 0;
  letter-spacing:.3px;
}
.analyst-workflow-card p {
  white-space:pre-wrap;
  color:#f4f1ff;
  line-height:1.5;
  margin:0;
}
.timeline-note {
  border-left:4px solid #b26cff;
  background:rgba(255,255,255,.035);
  border-radius:12px;
  padding:10px 12px;
  margin-bottom:10px;
}
.timeline-note strong {
  display:block;
  color:#ffd86b;
  font-size:12px;
  margin-bottom:4px;
}
.timeline-note p {
  margin:0;
  color:#f4f1ff;
}


.analyst-live-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:linear-gradient(180deg, rgba(38,22,55,.72), rgba(11,12,20,.95));
  padding:16px;
}
.analyst-live-header {
  display:flex;
  justify-content:space-between;
  gap:16px;
  align-items:flex-start;
  margin-bottom:14px;
}
.analyst-live-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:16px;
  margin:0 0 6px 0;
  letter-spacing:.3px;
}
.analyst-live-header p {
  color:#d7c4ef;
  margin:0;
  line-height:1.45;
}
.report-save-button {
  border:1px solid #b26cff;
  background:#281536;
  color:#fff;
  border-radius:999px;
  padding:9px 14px;
  cursor:pointer;
  font-weight:800;
  white-space:nowrap;
}
.report-save-button:hover {
  background:#3b1d55;
  box-shadow:0 0 16px rgba(178,108,255,.22);
}
.analyst-label {
  display:block;
  color:#ffd86b;
  font-size:12px;
  text-transform:uppercase;
  font-weight:900;
  margin:12px 0 6px 0;
}
.analyst-textarea {
  width:100%;
  min-height:82px;
  resize:vertical;
  box-sizing:border-box;
  border:1px solid #3b284d;
  border-radius:12px;
  background:#06070d;
  color:#f4f1ff;
  padding:12px;
  font-family:Segoe UI, Arial, sans-serif;
  font-size:13px;
  line-height:1.45;
}
.analyst-textarea.notes {
  min-height:140px;
}
.workflow-check-grid {
  display:grid;
  grid-template-columns:repeat(3, 1fr);
  gap:10px;
  margin-top:14px;
}
.workflow-check-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  font-size:12px;
}
.workflow-check-grid input {
  accent-color:#b26cff;
}
.embedded-analyst-summary {
  margin-top:14px;
  border:1px dashed #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
}
.embedded-analyst-summary h3 {
  color:#c27cff;
  margin:0 0 8px 0;
  text-transform:uppercase;
  font-size:13px;
}
.embedded-analyst-summary p,
.embedded-analyst-summary li {
  color:#f4f1ff;
  white-space:pre-wrap;
}

.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){
  .workflow-check-grid { grid-template-columns:1fr; }
  .analyst-live-header { display:block; }
  .report-save-button { margin-top:12px; }
}


.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){
  .playbook-card-grid { grid-template-columns:1fr; }
}


.kql-block { margin-top:10px; }
.kql-title { color:#ffd86b; font-weight:900; margin:8px 0 6px 0; font-size:12px; }
.kql-block pre { white-space:pre-wrap; word-break:break-word; background:#06070d; border:1px solid #3b284d; border-radius:12px; padding:12px; color:#e8ddff; font-size:12px; }


.analyst-workflow-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:14px;
  margin-bottom:12px;
}
.analyst-workflow-card h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:14px;
  margin:0 0 8px 0;
  letter-spacing:.3px;
}
.analyst-workflow-card p {
  white-space:pre-wrap;
  color:#f4f1ff;
  line-height:1.5;
  margin:0;
}
.timeline-note {
  border-left:4px solid #b26cff;
  background:rgba(255,255,255,.035);
  border-radius:12px;
  padding:10px 12px;
  margin-bottom:10px;
}
.timeline-note strong {
  display:block;
  color:#ffd86b;
  font-size:12px;
  margin-bottom:4px;
}
.timeline-note p {
  margin:0;
  color:#f4f1ff;
}


.analyst-live-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:linear-gradient(180deg, rgba(38,22,55,.72), rgba(11,12,20,.95));
  padding:16px;
}
.analyst-live-header {
  display:flex;
  justify-content:space-between;
  gap:16px;
  align-items:flex-start;
  margin-bottom:14px;
}
.analyst-live-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-size:16px;
  margin:0 0 6px 0;
  letter-spacing:.3px;
}
.analyst-live-header p {
  color:#d7c4ef;
  margin:0;
  line-height:1.45;
}
.report-save-button {
  border:1px solid #b26cff;
  background:#281536;
  color:#fff;
  border-radius:999px;
  padding:9px 14px;
  cursor:pointer;
  font-weight:800;
  white-space:nowrap;
}
.report-save-button:hover {
  background:#3b1d55;
  box-shadow:0 0 16px rgba(178,108,255,.22);
}
.analyst-label {
  display:block;
  color:#ffd86b;
  font-size:12px;
  text-transform:uppercase;
  font-weight:900;
  margin:12px 0 6px 0;
}
.analyst-textarea {
  width:100%;
  min-height:82px;
  resize:vertical;
  box-sizing:border-box;
  border:1px solid #3b284d;
  border-radius:12px;
  background:#06070d;
  color:#f4f1ff;
  padding:12px;
  font-family:Segoe UI, Arial, sans-serif;
  font-size:13px;
  line-height:1.45;
}
.analyst-textarea.notes {
  min-height:140px;
}
.workflow-check-grid {
  display:grid;
  grid-template-columns:repeat(3, 1fr);
  gap:10px;
  margin-top:14px;
}
.workflow-check-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  font-size:12px;
}
.workflow-check-grid input {
  accent-color:#b26cff;
}
.embedded-analyst-summary {
  margin-top:14px;
  border:1px dashed #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
}
.embedded-analyst-summary h3 {
  color:#c27cff;
  margin:0 0 8px 0;
  text-transform:uppercase;
  font-size:13px;
}
.embedded-analyst-summary p,
.embedded-analyst-summary li {
  color:#f4f1ff;
  white-space:pre-wrap;
}

.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){
  .workflow-check-grid { grid-template-columns:1fr; }
  .analyst-live-header { display:block; }
  .report-save-button { margin-top:12px; }
}


.report-save-status {
  display:none;
  border:1px solid #6ee7a0;
  border-radius:12px;
  background:rgba(255,255,255,.035);
  padding:10px 12px;
  margin-bottom:12px;
  font-size:12px;
  font-weight:800;
  line-height:1.35;
}


.report-save-actions {
  display:flex;
  flex-direction:column;
  align-items:flex-end;
  gap:6px;
}
.report-save-actions small {
  color:#d7c4ef;
  font-size:11px;
  text-align:right;
  max-width:260px;
  line-height:1.3;
}


.kql-parameter-summary {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:8px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:10px;
  margin:10px 0 14px 0;
}
.kql-parameter-summary strong {
  color:#c27cff;
  text-transform:uppercase;
  font-size:12px;
}
.kql-parameter-summary span {
  color:#f4f1ff;
  font-size:12px;
  overflow-wrap:anywhere;
}


.remediation-advisory{border:1px solid rgba(241,196,15,.45);border-radius:14px;background:rgba(241,196,15,.08);color:#ffd86b;padding:12px;margin-bottom:14px;line-height:1.45}
.remediation-card{border:1px solid #3b284d;border-radius:16px;background:rgba(255,255,255,.035);padding:14px;margin-bottom:14px}
.remediation-card-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start;border-bottom:1px solid #3b284d;padding-bottom:10px;margin-bottom:12px}
.remediation-card h3{color:#c27cff;text-transform:uppercase;font-size:15px;margin:0 0 6px 0}
.remediation-card p{color:#f4f1ff;margin:0;line-height:1.45}
.remediation-steps{display:grid;gap:10px}
.remediation-step{display:grid;grid-template-columns:30px 1fr 150px;gap:10px;align-items:start;border:1px solid #3b284d;border-radius:12px;background:rgba(255,255,255,.025);padding:10px}
.remediation-step span{width:26px;height:26px;display:grid;place-items:center;border-radius:999px;background:#321846;border:1px solid #b26cff;color:#fff;font-weight:900;font-size:12px}
.remediation-step select{background:#06070d;color:#f4f1ff;border:1px solid #56336f;border-radius:10px;padding:7px}

.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){.remediation-step{grid-template-columns:30px 1fr}.remediation-step select{grid-column:2}.remediation-card-head{display:block}}


.workflow-maturity-intro,.timeline-correlation-help {
  border:1px solid #56336f;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  color:#f4f1ff;
  padding:12px;
  margin-bottom:12px;
}
.workflow-stage-grid,.section-notes-grid {
  display:grid;
  grid-template-columns:repeat(3, minmax(0,1fr));
  gap:12px;
}
.workflow-stage-card,.section-note-card,.gap-closure-card {
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.035);
  padding:12px;
}
.workflow-stage-card span,.gap-closure-card h3,.section-note-card h3,.disposition-header h3 {
  color:#c27cff;
  text-transform:uppercase;
  font-weight:900;
  font-size:13px;
  margin:0 0 8px 0;
}
.workflow-stage-card p,.gap-closure-card p,.disposition-header p {
  color:#f4f1ff;
  line-height:1.45;
  margin:0;
}
.disposition-panel {
  border:1px solid #56336f;
  border-radius:16px;
  background:rgba(255,255,255,.035);
  padding:14px;
}
.disposition-grid {
  display:grid;
  grid-template-columns:repeat(4, minmax(0, 1fr));
  gap:10px;
  margin:12px 0;
}
.disposition-grid label {
  border:1px solid #3b284d;
  border-radius:12px;
  padding:9px 10px;
  background:rgba(255,255,255,.025);
  color:#f4f1ff;
  font-size:12px;
}
.disposition-grid input { accent-color:#b26cff; }
.timeline-correlation-item {
  display:grid;
  grid-template-columns:34px 1fr;
  gap:10px;
  border:1px solid #3b284d;
  border-radius:14px;
  background:rgba(255,255,255,.025);
  padding:12px;
  margin-bottom:10px;
}
.timeline-index {
  width:28px;
  height:28px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
}
.timeline-correlation-item p {
  color:#f4f1ff;
  margin:7px 0 0 0;
  line-height:1.45;
}
.gap-closure-card { margin-bottom:12px; }
.gap-closure-card ol {
  list-style:none;
  padding:0;
  margin:12px 0 0 0;
  display:grid;
  gap:8px;
}
.gap-closure-card li {
  display:grid;
  grid-template-columns:30px 1fr;
  gap:10px;
}
.gap-closure-card li span {
  width:24px;
  height:24px;
  display:grid;
  place-items:center;
  border-radius:999px;
  background:#321846;
  border:1px solid #b26cff;
  color:#fff;
  font-weight:900;
  font-size:12px;
}
.kql-validation-panel table {
  width:100%;
  border-collapse:collapse;
}
.kql-validation-panel th,.kql-validation-panel td {
  border:1px solid #3b284d;
  padding:8px;
  text-align:left;
  vertical-align:top;
}
.kql-validation-panel p {
  color:#d7c4ef;
}
@media(max-width:1200px){
  .workflow-stage-grid,.section-notes-grid,.disposition-grid { grid-template-columns:1fr; }
}

@media(max-width:1200px){ .layout{grid-template-columns:1fr;} .left,.right{position:static;} .main-two{grid-template-columns:1fr;} .metrics{grid-template-columns:repeat(2,1fr);} .meta{grid-template-columns:1fr 1fr;} .hero{grid-template-columns:1fr;} }
</style>
</head>
<body>
<div class="shell">
  <section class="hero">
    <div>
      <h1>SHADOW TRACE <span class="ops">OPS</span></h1>
      <div class="subtitle">Primary Investigation Dashboard - post-authentication correlation and defensive gap assessment</div>
      <div class="meta">
        <div><span>Generated</span>$(Get-Date)</div>
        <div><span>Target User</span>$(ConvertTo-SafeHtml $upn)</div>
        <div><span>Lookback</span>$($Script:Investigation.AuthLookbackDays) day(s)</div>
        <div><span>Run Mode</span>$($Script:Investigation.RunMode)</div>
      </div>
    </div>
    <div class="logo-area">$logoHtml</div>
  </section>

  <div class="layout">
    <aside class="left">
      <div class="panel"><h2>Modules</h2>$($moduleNav -join "`n")<a class="module-link review" href="#workflow-maturity"><span>Investigation Workflow</span><strong>6 Steps</strong></a><a class="module-link review" href="#investigation-disposition"><span>Disposition</span><strong>Status</strong></a><a class="module-link review" href="#section-analyst-notes"><span>Section Notes</span><strong>Notes</strong></a><a class="module-link review" href="#timeline-correlation"><span>Timeline Correlation</span><strong>Pivot</strong></a><a class="module-link review" href="#gap-closure-guidance"><span>Gap Closure</span><strong>Controls</strong></a><a class="module-link review" href="#kql-validation"><span>KQL Validation</span><strong>Templates</strong></a><a class="module-link review" href="#potential-remediation"><span>Potential Remediation</span><strong>Steps</strong></a><a class="module-link review" href="#analyst-workflow"><span>Analyst Workflow</span><strong>Notes</strong></a><a class="module-link review" href="#playbooks"><span>Investigation Playbooks</span><strong>JSON</strong></a></div>
    </aside>

    <main>
      <div class="metrics">
        <div class="metric"><div class="icon">AUTH</div><div class="num">$authCount</div><div class="label">Auth Items</div></div>
        <div class="metric"><div class="icon">RISK</div><div class="num">$identityCount</div><div class="label">Risk Items</div></div>
        <div class="metric"><div class="icon">CLOUD</div><div class="num">$cloudCount</div><div class="label">Cloud Items</div></div>
        <div class="metric"><div class="icon">XDR</div><div class="num">$endpointXdrCount</div><div class="label">Endpoint/XDR</div></div>
        <div class="metric"><div class="icon">URL</div><div class="num">$emailUrlCount</div><div class="label">Email/URL</div></div>
        <div class="metric"><div class="icon">GAPS</div><div class="num">$gapCount</div><div class="label">Potential Gaps</div></div>
      </div>

      <div class="main-two">
        <div class="card">
          <h2>Where to Start</h2>
          <div class="donut-wrap">
            <div class="donut" style="background:conic-gradient($($segments -join ', '));"><div class="hole"><strong>$total</strong><span>Total Signals</span></div></div>
            <div class="legend">$($legend -join "`n")</div>
          </div>
          $priorityHtml
        </div>
        <div class="card score-card-panel">
          <h2>Investigation Score</h2>
          <div class="score-grid">
            <div class="score-box"><strong>$score</strong><span>Score</span></div>
            <div class="score-box"><strong>$classification</strong><span>Classification</span></div>
            <div class="score-box"><strong>$confidence</strong><span>Confidence</span></div>
          </div>
          <div class="risk-meter">
            <div class="risk-band low"><span>Low</span><small>0-2</small></div>
            <div class="risk-band medium"><span>Medium</span><small>3-5</small></div>
            <div class="risk-band high"><span>High</span><small>6-8</small></div>
            <div class="risk-band critical"><span>Critical</span><small>9+</small></div>
            <div class="risk-needle" style="left:$scoreNeedleLeft%"></div>
          </div>
          <div class="risk-definitions">
            <div><strong>Low:</strong> routine review.</div>
            <div><strong>Medium:</strong> analyst review recommended.</div>
            <div><strong>High:</strong> prompt investigation.</div>
            <div><strong>Critical:</strong> immediate review.</div>
          </div>
          <div class="score-reasons">
            <h3>Why this score?</h3>
            $scoreContributorHtml
          </div>
        </div>
      </div>

      <details open id="summary"><summary>Executive Summary</summary><div class="detail-body">$summaryTable</div></details>
      <details open id="identity-risk"><summary>Identity Risk</summary><div class="detail-body">$identityCards</div></details>
      <details id="authentication"><summary>Authentication</summary><div class="detail-body">$authCards</div></details>
      <details id="email-url"><summary>Email / URL Activity</summary><div class="detail-body">$emailCards</div></details>
      <details id="endpoint-xdr"><summary>Endpoint / XDR</summary><div class="detail-body">$xdrCards</div></details>
      <details id="cloud-activity"><summary>Cloud Activity</summary><div class="detail-body">$cloudCards</div></details>
      <details id="oauth"><summary>OAuth / App Access</summary><div class="detail-body">$oauthCards</div></details>
      <details id="gaps"><summary>Gaps & Exposures</summary><div class="detail-body">$gapCards</div></details>
      <details id="playbooks" open><summary>Investigation Playbooks</summary><div class="detail-body"><p>Click a playbook card to open analyst guidance in a side panel. JSON source files remain in <strong>Toolkit\Config\Playbooks</strong>.</p>$kqlParameterSummaryHtml$playbookHtml</div></details>
      
      <details open id="workflow-maturity"><summary>Investigation Workflow</summary><div class="detail-body">$workflowMaturityHtml</div></details>
      <details open id="investigation-disposition"><summary>Investigation Disposition</summary><div class="detail-body">$dispositionHtml</div></details>
      <details id="section-analyst-notes"><summary>Per-Section Analyst Notes</summary><div class="detail-body">$perSectionNotesHtml</div></details>
      <details id="timeline-correlation"><summary>Timeline Correlation</summary><div class="detail-body">$timelineCorrelationHtml</div></details>
      <details id="gap-closure-guidance"><summary>Gap Closure Guidance</summary><div class="detail-body">$gapClosureHtml</div></details>
      <details id="kql-validation"><summary>KQL Template Validation</summary><div class="detail-body">$kqlValidationHtml</div></details>

      <details open id="potential-remediation"><summary>Potential Remediation Steps</summary><div class="detail-body">$potentialRemediationHtml</div></details>
      <details open id="analyst-workflow"><summary>Analyst Workflow & Notes</summary><div class="detail-body">$analystWorkflowHtml</div></details>
      <details id="analyst-timeline"><summary>Analyst Timeline Annotations</summary><div class="detail-body">$analystTimelineHtml</div></details>
      <details id="source-health"><summary>Source Health</summary><div class="detail-body">$sourceCards</div></details>
    </main>

    <aside class="right">
      <div class="panel report-summary-panel">
        <h2>Report Summary</h2>
        <div class="summary-kv"><span>User</span><strong>$(ConvertTo-SafeHtml $upn)</strong></div>
        <div class="summary-kv"><span>Priority</span><strong>$(ConvertTo-SafeHtml $Script:Investigation.Priority)</strong></div>
        <div class="summary-kv"><span>Profile</span><strong>$(ConvertTo-SafeHtml $Script:Investigation.InvestigationProfile)</strong></div>
        <div class="summary-kv"><span>Readiness</span><strong>$(ConvertTo-SafeHtml $Script:Investigation.ProductReadiness)</strong></div>

        <div class="score-priority-explainer">
          <div class="explainer-card $scoreClassCss">
            <span>Investigation Score</span>
            <strong>$score / Technical Signal Severity</strong>
            <small>$(ConvertTo-SafeHtml $scoreMeaning)</small>
          </div>
          <div class="explainer-card priority-card-note">
            <span>Priority</span>
            <strong>Analyst Workflow Recommendation</strong>
            <small>$(ConvertTo-SafeHtml $priorityMeaning)</small>
          </div>
        </div>
      </div>
      <div class="panel"><h2>Key Findings</h2>$findings</div>
      <div class="panel"><h2>Recommendations</h2>$recommendations</div>
      <div class="panel actions"><h2>Actions</h2><a href="#summary">Review Summary</a><a href="#potential-remediation">Review Remediation Steps</a><a href="#analyst-workflow">Review Analyst Notes</a><a href="#playbooks">Open Playbooks Section</a><a href="#gaps">Review Gaps</a><a href="#source-health">Review Source Health</a><div class="report-card"><span class="status-tag tag-review">Folder</span>JSON playbooks are stored in Toolkit\Config\Playbooks.</div></div>
    </aside>
  </div>

  <div class="footer"><span>Shadow Trace Ops - Investigate. Correlate. Protect.</span><span>This is the Primary Dashboard report.</span></div>
</div>
</body>
</html>
"@

        $html | Out-File -FilePath $reportFile -Encoding UTF8
        Test-ShadowTraceHtmlReportFile -Path $reportFile -ReportName "Primary dashboard report" | Out-Null
        $Script:CurrentReportFile = $reportFile
        Write-ToolLog "PRIMARY DASHBOARD report exported: $reportFile" "SUCCESS"
        return $reportFile
    }
    catch {
        Write-ToolLog "Primary Dashboard export failed: $($_.Exception.Message)" "ERROR"
        return $null
    }
}



function Export-InvestigationReport {
    
    if (-not (Test-CanExportShadowTraceReport)) { return $null }
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
        Save-AnalystWorkflowToInvestigation
        Set-CollectionStatus -Name "ReportExport" -Status "Running"

        $selectedReportMode = "Investigation"
        try { if ($Script:cmbRunMode -and $Script:cmbRunMode.SelectedItem) { $selectedReportMode = [string]$Script:cmbRunMode.SelectedItem } } catch {}
        if ($selectedReportMode -eq "Executive Report") {
            $executiveReport = Export-ExecutiveExposureReport
            Set-CollectionStatus -Name "ReportExport" -Status "Completed"
            if ($executiveReport -and (Test-Path $executiveReport)) {
                $Script:CurrentReportFile = $executiveReport
                $Script:CurrentSnapshotReport = $executiveReport
                Start-Process $executiveReport
                Write-ToolLog "Opened Executive report: $executiveReport" "SUCCESS"
            }
            return
        }

        $dashboardReport = Export-PrimaryDashboardReport
        $snapshotReport = Export-ExecutiveExposureReport
        $detailReport = Export-DetailedWorkflowReport -SummaryReportPath $dashboardReport

        if (Get-Command Export-InvestigationJson -ErrorAction SilentlyContinue) {
            Export-InvestigationJson
        }

        Set-CollectionStatus -Name "ReportExport" -Status "Completed"

        if ($dashboardReport -and (Test-Path $dashboardReport)) {
            $Script:CurrentReportFile = $dashboardReport
            Start-Process $dashboardReport
            Write-ToolLog "Opened Primary Dashboard report: $dashboardReport" "SUCCESS"
        }

        if ($detailReport -and (Test-Path $detailReport)) {
            Write-ToolLog "Detailed workflow report available: $detailReport" "INFO"
        }
    }
    catch {
        Set-CollectionStatus -Name "ReportExport" -Status "Failed"
        Write-ToolLog "Report export failed: $($_.Exception.Message)" "ERROR"
    }
}




function Open-ExecutiveReport {
    if ($Script:CurrentSnapshotReport -and (Test-Path $Script:CurrentSnapshotReport)) {
        Start-Process $Script:CurrentSnapshotReport
        Write-ToolLog "Opened Executive report: $Script:CurrentSnapshotReport" "INFO"
        return
    }

    $latestExecutive = Get-ChildItem -Path $Script:ReportPath -Filter "ShadowTraceOps-ExecutiveReport-*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestExecutive) {
        $Script:CurrentSnapshotReport = $latestExecutive.FullName
        Start-Process $latestExecutive.FullName
        Write-ToolLog "Opened latest Executive report: $($latestExecutive.FullName)" "INFO"
        return
    }

    [System.Windows.Forms.MessageBox]::Show(
        "No Executive report was found. Run an investigation and click Export HTML Report first.",
        "No Executive Report Found",
        "OK",
        "Information"
    ) | Out-Null
}

function Open-CurrentReport {
    if ($Script:CurrentReportFile -and (Test-Path $Script:CurrentReportFile)) {
        Start-Process $Script:CurrentReportFile
        return
    }

    $latestDashboard = Get-ChildItem -Path $Script:ReportPath -Filter "ShadowTraceOps-PrimaryDashboard-*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestDashboard) {
        $Script:CurrentReportFile = $latestDashboard.FullName
        Start-Process $latestDashboard.FullName
        return
    }

    $latestAny = Get-ChildItem -Path $Script:ReportPath -Filter "*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestAny) {
        $Script:CurrentReportFile = $latestAny.FullName
        Start-Process $latestAny.FullName
        return
    }

    [System.Windows.Forms.MessageBox]::Show("No report was found. Run an investigation and export the report first.","No Report Found","OK","Information") | Out-Null
}

function Clear-InvestigationLog {
    $Script:txtLog.Clear()
    Write-ToolLog "On-screen log cleared. File logging continues at: $Script:LogFile" "INFO"
}

# ------------------------------------------------------------
# GUI
# ------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Shadow Trace Ops - Phase 1"
$form.Size = New-Object System.Drawing.Size(1120, 900)
$form.StartPosition = "CenterScreen"
$form.BackColor = $Script:Theme.FormBack
$form.ForeColor = $Script:Theme.TextFore
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "Shadow Trace Ops"
$title.Location = New-Object System.Drawing.Point(20, 15)
$title.Size = New-Object System.Drawing.Size(850, 34)
$title.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $Script:Theme.AccentStrong
$title.BackColor = $Script:Theme.FormBack
$form.Controls.Add($title)

$phase = New-Object System.Windows.Forms.Label
$phase.Text = "Phase 1 - Shadow Trace Ops read-only post-authentication investigation, XDR correlation, and defensive gap assessment"
$phase.Location = New-Object System.Drawing.Point(22, 50)
$phase.Size = New-Object System.Drawing.Size(850, 22)
$phase.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$phase.ForeColor = $Script:Theme.MutedFore
$phase.BackColor = $Script:Theme.FormBack
$form.Controls.Add($phase)

$form.Controls.Add((New-SectionLabel "Investigation Target" 20 85))

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "User Principal Name:"
$lblUser.Location = New-Object System.Drawing.Point(20, 120)
$lblUser.Size = New-Object System.Drawing.Size(160, 24)
$lblUser.ForeColor = $Script:Theme.TextFore
$lblUser.BackColor = $Script:Theme.FormBack
$form.Controls.Add($lblUser)

$Script:txtUser = New-Object System.Windows.Forms.TextBox
$Script:txtUser.Location = New-Object System.Drawing.Point(180, 117)
$Script:txtUser.Size = New-Object System.Drawing.Size(360, 24)
$Script:txtUser.BackColor = $Script:Theme.InputBack
$Script:txtUser.ForeColor = $Script:Theme.TextFore
$Script:txtUser.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($Script:txtUser)

$lblAuthLookbackTop = New-Object System.Windows.Forms.Label
$lblAuthLookbackTop.Text = "Auth Log Drilldown:"
$lblAuthLookbackTop.Location = New-Object System.Drawing.Point(570, 120)
$lblAuthLookbackTop.Size = New-Object System.Drawing.Size(145, 24)
$lblAuthLookbackTop.ForeColor = $Script:Theme.TextFore
$lblAuthLookbackTop.BackColor = $Script:Theme.FormBack
$form.Controls.Add($lblAuthLookbackTop)

$Script:cmbAuthLookback = New-Object System.Windows.Forms.ComboBox
$Script:cmbAuthLookback.Location = New-Object System.Drawing.Point(720, 117)
$Script:cmbAuthLookback.Size = New-Object System.Drawing.Size(135, 24)
$Script:cmbAuthLookback.DropDownStyle = "DropDownList"
$Script:cmbAuthLookback.BackColor = $Script:Theme.InputBack
$Script:cmbAuthLookback.ForeColor = $Script:Theme.TextFore
$Script:cmbAuthLookback.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
[void]$Script:cmbAuthLookback.Items.Add("7 days")
[void]$Script:cmbAuthLookback.Items.Add("30 days")
[void]$Script:cmbAuthLookback.Items.Add("90 days")
$Script:cmbAuthLookback.SelectedIndex = 0
$form.Controls.Add($Script:cmbAuthLookback)

$lblRunMode = New-Object System.Windows.Forms.Label
$lblExecutiveNote = New-Object System.Windows.Forms.Label
$lblExecutiveNote.Text = "Executive Report: created by Export HTML Report"
$lblExecutiveNote.Location = New-Object System.Drawing.Point(570, 145)
$lblExecutiveNote.Size = New-Object System.Drawing.Size(420, 20)
$lblExecutiveNote.ForeColor = $Script:Theme.MutedFore
$form.Controls.Add($lblExecutiveNote)

$lblRunMode.Text = "Run Mode:"
$lblRunMode.Location = New-Object System.Drawing.Point(875, 120)
$lblRunMode.Size = New-Object System.Drawing.Size(75, 24)
$lblRunMode.ForeColor = $Script:Theme.TextFore
$lblRunMode.BackColor = $Script:Theme.FormBack
$form.Controls.Add($lblRunMode)

$Script:cmbRunMode = New-Object System.Windows.Forms.ComboBox
$Script:cmbRunMode.Location = New-Object System.Drawing.Point(950, 117)
$Script:cmbRunMode.Size = New-Object System.Drawing.Size(125, 24)
$Script:cmbRunMode.DropDownStyle = "DropDownList"
$Script:cmbRunMode.BackColor = $Script:Theme.InputBack
$Script:cmbRunMode.ForeColor = $Script:Theme.TextFore
$Script:cmbRunMode.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
[void]$Script:cmbRunMode.Items.Add("Investigation")
[void]$Script:cmbRunMode.Items.Add("Executive Report")
$Script:cmbRunMode.SelectedIndex = 0
$form.Controls.Add($Script:cmbRunMode)

$form.Controls.Add((New-SectionLabel "Investigation Workflow" 20 165 420))

$workflow = New-Object System.Windows.Forms.Label
$workflow.Text = "Identity Risk -> Authentication -> Cloud Activity -> Session Behavior -> Findings -> Potential Gaps -> Recommendations"
$workflow.Location = New-Object System.Drawing.Point(20, 198)
$workflow.Size = New-Object System.Drawing.Size(1030, 30)
$workflow.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$workflow.ForeColor = $Script:Theme.TextFore
$workflow.BackColor = $Script:Theme.FormBack
$form.Controls.Add($workflow)

$form.Controls.Add((New-SectionLabel "Investigation Scope" 20 245 420))



# Authentication log drilldown selector moved to the Investigation Target row for better visibility.

$form.Controls.Add((New-SectionLabel "Actions" 20 430 420))

# Buttons are intentionally spaced across two rows to avoid crowding as the toolkit grows.

$Script:chkRuntimeHunting = New-Object System.Windows.Forms.CheckBox
$Script:chkRuntimeHunting.Text = "Enable Runtime Advanced Hunting collectors (optional)"
$Script:chkRuntimeHunting.Location = New-Object System.Drawing.Point(30, 272)
$Script:chkRuntimeHunting.Size = New-Object System.Drawing.Size(430, 24)
$Script:chkRuntimeHunting.Checked = $false
$Script:chkRuntimeHunting.BackColor = $Script:Theme.PanelBack
$Script:chkRuntimeHunting.ForeColor = $Script:Theme.TextFore
$Script:chkRuntimeHunting.Add_CheckedChanged({
    $Script:EnableRuntimeAdvancedHunting = $Script:chkRuntimeHunting.Checked
    Write-ToolLog ("Runtime Advanced Hunting collectors enabled: {0}" -f $Script:EnableRuntimeAdvancedHunting) "INFO"
})
$form.Controls.Add($Script:chkRuntimeHunting)

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

$btnOpenExecutive = New-Button -Text "Open Executive" -X 920 -Y 315 -OnClick { Open-ExecutiveReport } -W 160 -H 34
$btnOpenExecutive.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
$btnOpenExecutive.ForeColor = [System.Drawing.Color]::White
$btnOpenExecutive.FlatAppearance.BorderColor = [System.Drawing.Color]::Black
$btnOpenExecutive.FlatAppearance.BorderSize = 2
$form.Controls.Add($btnExecutive)

$btnLogs = New-Button "Open Logs" 920 465 { Start-Process $Script:LogPath }
$form.Controls.Add($btnLogs)

$btnConfig = New-Button "Open Config" 20 512 { Start-Process $Script:ConfigPath }
$form.Controls.Add($btnConfig)

$btnExports = New-Button "Open Exports" 200 512 { Start-Process $Script:ExportPath }
$form.Controls.Add($btnExports)

$btnJsonExport = New-Button "Export JSON Executive" 380 512 { Export-InvestigationJson }
$form.Controls.Add($btnJsonExport)

$btnClearLog = New-Button "Clear Log View" 560 512 { Clear-InvestigationLog }
$form.Controls.Add($btnClearLog)

$btnExit = New-Button "Exit" 740 512 { $form.Close() }
$form.Controls.Add($btnExit)



# Analyst workflow is entered directly in the HTML report.


$Script:txtLog = New-Object System.Windows.Forms.TextBox
$Script:txtLog.Location = New-Object System.Drawing.Point(20, 570)
$Script:txtLog.Size = New-Object System.Drawing.Size(1060, 280)
$Script:txtLog.Multiline = $true
$Script:txtLog.ScrollBars = "Vertical"
$Script:txtLog.ReadOnly = $true
$Script:txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$Script:txtLog.BackColor = $Script:Theme.LogBack
$Script:txtLog.ForeColor = $Script:Theme.LogFore
$Script:txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($Script:txtLog)

Set-DarkControlStyle -Control $form
Add-LogoToForm -Form $form

Write-ToolLog "Shadow Trace Ops loaded." "SUCCESS"
Write-ToolLog "Phase 1 mode: read-only and advisory." "INFO"
Write-ToolLog "Dark mode interface enabled." "INFO"
Write-ToolLog "Log file: $Script:LogFile" "INFO"
Write-ToolLog "Reports path: $Script:ReportPath" "INFO"
Write-ToolLog "Assets path: $Script:AssetPath" "INFO"

[void]
try {
    if ($Script:cmbRunMode) {
        $Script:cmbRunMode.Add_SelectedIndexChanged({
            try { Write-ToolLog "Report mode changed to: $($Script:cmbRunMode.SelectedItem)" "INFO" } catch {}
        })
    }
} catch {}

$form.ShowDialog()

function Set-AllInvestigationScopeToggles {
    param([bool]$Checked)

    $Script:SuppressScopeToggleEvents = $true
    try {
        foreach ($toggle in (Get-InvestigationScopeToggles)) {
            if ($toggle) { $toggle.Checked = $Checked }
        }

        if ($Script:chkSelectAllScope) {
            $Script:chkSelectAllScope.Checked = $Checked
            $Script:chkSelectAllScope.Text = if ($Checked) { "Select All Scope" } else { "Select All Scope" }
        }
    }
    finally {
        $Script:SuppressScopeToggleEvents = $false
    }
}
function Update-SelectAllScopeState {
    if ($Script:SuppressScopeToggleEvents) { return }

    $toggles = @(Get-InvestigationScopeToggles)
    if ($toggles.Count -eq 0 -or -not $Script:chkSelectAllScope) { return }

    $checkedCount = ($toggles | Where-Object { $_.Checked }).Count
    $allChecked = ($checkedCount -eq $toggles.Count)

    $Script:SuppressScopeToggleEvents = $true
    try {
        $Script:chkSelectAllScope.Checked = $allChecked
        $Script:chkSelectAllScope.Text = "Select All Scope"
    }
    finally {
        $Script:SuppressScopeToggleEvents = $false
    }
}