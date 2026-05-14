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
  <div class='metric-card'><div class='metric-icon'>◆</div><div class='metric-value'>$authCount</div><div class='metric-label'>Auth Items</div></div>
  <div class='metric-card'><div class='metric-icon'>▲</div><div class='metric-value'>$riskCount</div><div class='metric-label'>Risk Items</div></div>
  <div class='metric-card'><div class='metric-icon'>☁</div><div class='metric-value'>$cloudCount</div><div class='metric-label'>Cloud Items</div></div>
  <div class='metric-card'><div class='metric-icon'>◎</div><div class='metric-value'>$xdrCount</div><div class='metric-label'>XDR Items</div></div>
  <div class='metric-card'><div class='metric-icon'>↗</div><div class='metric-value'>$urlCount</div><div class='metric-label'>URL Click Items</div></div>
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
        $arrow = if ($i -lt ($Steps.Count - 1)) { "<div class='flow-arrow'>→</div>" } else { "" }
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
    $($stepHtml -join "<div class='flow-arrow'>→</div>")
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
        ObservedRisks       = @()
        PotentialGaps       = @()
        Recommendations     = @()
        InvestigationPivots = @()
        Priority            = "Review Required"
        AuthLookbackDays    = 7
        RunMode             = "Standard"
        MaxQueryRows        = 10
        HuntingLookbackDays = 3
        InvestigationProfile = "Standard 7d - Normal investigation"
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
        return "Query syntax or schema issue"
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
        Write-ToolLog "Advanced Hunting requires supported Defender XDR data, ThreatHunting.Read.All, and appropriate role access." "WARN"

        Add-SourceHealthItem -CollectorName $CollectorName -Status "Failed" -RowsReturned 0 -DurationSeconds $duration -Detail "$classification. Raw error: $($_.Exception.Message)"
        return [ordered]@{
            Failed         = $true
            Classification = $classification
            ErrorMessage   = $_.Exception.Message
            Rows           = @()
        }
    }
}

function Get-EndpointContextPhase1 {
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

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
            Set-CollectionStatus -Name "EndpointContext" -Status "Failed - Query syntax or schema issue"
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
            Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint Advanced Hunting query could not be completed. Classification: $($rows.Classification). Review ThreatHunting.Read.All, Defender XDR role access, and availability of DeviceLogonEvents."
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
        Set-CollectionStatus -Name "EndpointContext" -Status "Failed"
        Add-UniqueInvestigationItem -Section "EndpointContext" -Value "Endpoint context collection could not be completed. Review Defender XDR access, advanced hunting availability, and endpoint permissions."
        Write-ToolLog "Endpoint context collection failed: $($_.Exception.Message)" "WARN"
    }
}

function Get-EmailPhishingContextPhase1 {
    param(
        [string]$UserPrincipalName,
        [int]$LookbackDays = 7
    )

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
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Failed - Query syntax or schema issue"
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

    Set-CollectionStatus -Name "UserResolution" -Status "Running"
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
        Set-CollectionStatus -Name "UserResolution" -Status "Completed"
        return $user
    }
    catch {
        Set-CollectionStatus -Name "UserResolution" -Status "Failed"
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

function Test-RunModeSafety {
    param(
        [int]$LookbackDays,
        [string]$RunMode
    )

    if ($RunMode -eq "Expanded" -and $LookbackDays -eq 90) {
        [System.Windows.Forms.MessageBox]::Show(
            "Expanded mode with a 90-day lookback is intentionally blocked to prevent long-running Advanced Hunting queries. Use 30 days in Expanded mode, or switch to Standard mode for 90 days.",
            "Expanded Mode Safety Guard",
            "OK",
            "Warning"
        ) | Out-Null
        Write-ToolLog "Expanded mode with 90-day lookback was blocked by the safety guard." "WARN"
        return $false
    }

    if ($RunMode -eq "Expanded") {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Expanded mode runs deeper Advanced Hunting queries and may take longer. Continue?",
            "Confirm Expanded Mode",
            "YesNo",
            "Warning"
        )

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-ToolLog "Expanded mode run was cancelled by the user." "WARN"
            return $false
        }
    }

    return $true
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

    $lookbackDays = [int]$Script:cmbAuthLookback.SelectedItem.ToString().Replace(" days", "")
    $runMode = $Script:cmbRunMode.SelectedItem.ToString()
    if (-not (Test-RunModeSafety -LookbackDays $lookbackDays -RunMode $runMode)) {
        return
    }

    $Script:Investigation.AuthLookbackDays = $lookbackDays
    $Script:Investigation.RunMode = $runMode

    if ($runMode -eq "Expanded") {
        $Script:Investigation.MaxQueryRows = 50
        $Script:Investigation.HuntingLookbackDays = $lookbackDays
        $Script:Investigation.IsSummaryOnlyRun = $false

        if ($lookbackDays -eq 7) {
            $Script:Investigation.InvestigationProfile = "Expanded 7d - Deep investigation"
        }
        elseif ($lookbackDays -eq 30) {
            $Script:Investigation.InvestigationProfile = "Expanded 30d - Deep targeted hunt"
        }
    }
    else {
        $Script:Investigation.MaxQueryRows = 10
        $Script:Investigation.HuntingLookbackDays = [Math]::Min($lookbackDays, 3)

        if ($lookbackDays -eq 90) {
            $Script:Investigation.IsSummaryOnlyRun = $true
            $Script:Investigation.InvestigationProfile = "Standard 90d - Historical summary only"
        }
        elseif ($lookbackDays -eq 30) {
            $Script:Investigation.IsSummaryOnlyRun = $false
            $Script:Investigation.InvestigationProfile = "Standard 30d - Broader trend review"
        }
        else {
            $Script:Investigation.IsSummaryOnlyRun = $false
            $Script:Investigation.InvestigationProfile = "Standard 7d - Normal investigation"
        }
    }

    Write-ToolLog "Starting Phase 1 post-authentication investigation for $UserPrincipalName" "INFO"
    Write-ToolLog "Authentication log drill-down selected: $lookbackDays day(s)." "INFO"
    Write-ToolLog "Run mode selected: $runMode. Profile=$($Script:Investigation.InvestigationProfile). MaxQueryRows=$($Script:Investigation.MaxQueryRows). HuntingLookbackDays=$($Script:Investigation.HuntingLookbackDays). SummaryOnly=$($Script:Investigation.IsSummaryOnlyRun)." "INFO"
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
        if ($runMode -eq "Expanded" -and -not $Script:Investigation.IsSummaryOnlyRun) {
            Get-UrlClickContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $Script:Investigation.HuntingLookbackDays
        }
        else {
            Add-UniqueInvestigationItem -Section "UrlClickContext" -Value "URL click context skipped in Standard mode. Use Expanded mode for deeper URL click hunting."
            Set-CollectionStatus -Name "UrlClickContext" -Status "Skipped - Standard mode"
        }
        if ($runMode -eq "Expanded" -and -not $Script:Investigation.IsSummaryOnlyRun) {
            Get-CloudAppEventsContextPhase1 -UserPrincipalName $UserPrincipalName -LookbackDays $Script:Investigation.HuntingLookbackDays
        }
        else {
            Add-UniqueInvestigationItem -Section "CloudAppEvents" -Value "CloudAppEvents hunting skipped in Standard mode. Use Expanded mode for deeper Defender for Cloud Apps activity hunting."
            Set-CollectionStatus -Name "CloudAppEvents" -Status "Skipped - Standard mode"
        }
        Invoke-CloudSessionGapAssessmentPhase1
        Invoke-Phase1AssessmentLogic
        Build-UnifiedTimelinePhase1
        Add-Phase1ReadOnlyReminder

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

function Export-DetailedWorkflowReport {
    param([string]$SummaryReportPath)

    if (-not $Script:Investigation) { return $null }

    try {
        $upn = $Script:Investigation.UserPrincipalName
        $safeName = $upn.Replace("@", "_").Replace(".", "_").Replace("\", "_").Replace("/", "_")
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $detailFile = Join-Path $Script:ReportPath "ShadowTraceOps-DetailedWorkflow-$safeName-$timestamp.html"

        $logoHtml = Get-LogoHtml
        $tenantLogoHtml = Get-TenantLogoHtml
        $userSummaryTable = ConvertTo-HtmlTableFromHashtable $Script:Investigation.UserSummary
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
          <div><span>Run Mode:</span> $($Script:Investigation.RunMode)</div>
          <div><span>Profile:</span> $($Script:Investigation.InvestigationProfile)</div>
      <div><span>Priority:</span> $($Script:Investigation.Priority)</div>
      <div><span>Profile:</span> $($Script:Investigation.InvestigationProfile)</div>
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
</body>
</html>
"@

        $html | Out-File -FilePath $detailFile -Encoding UTF8
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
        $reportFile = Join-Path $Script:ReportPath "ShadowTraceOps-Investigation-$safeName-$timestamp.html"

        Write-ToolLog "Exporting HTML investigation report for $upn" "INFO"

        $userSummaryTable = ConvertTo-HtmlTableFromHashtable $Script:Investigation.UserSummary
        $logoHtml = Get-LogoHtml
        $tenantLogoHtml = Get-TenantLogoHtml
        $metricCardsHtml = Get-ReportMetricCardsHtml
        $executiveFlow = New-PivotDiagramHtml -Title "Shadow Trace Ops Investigation Path" -Steps @("Identity risk", "Authentication", "Email / URL", "Endpoint / XDR", "Cloud activity", "Gaps / recommendations")
        $collectionStatusTable = Convert-CollectionStatusToHtml
        $identityRiskItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.IdentityRisk -EmptyMessage "No identity risk findings were collected."
        $identityFlow = New-PivotDiagramHtml -Title "Identity Risk Review Path" -Steps @("Risky user status", "Risk detections", "Sign-in risk", "Control response", "Session trust decision")
        $authenticationItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Authentication -EmptyMessage "No authentication records were collected."
        $authFlow = New-PivotDiagramHtml -Title "Authentication Review Path" -Steps @("Successful auth", "MFA / CA result", "Device trust", "IP / location", "Post-auth activity")
        $cloudActivityItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.CloudActivity -EmptyMessage "No cloud activity notes were collected."
        $cloudFlow = New-PivotDiagramHtml -Title "Cloud Activity Review Path" -Steps @("App access", "File activity", "Downloads/uploads", "Sharing/OAuth", "Data movement review")
        $sessionBehaviorItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.SessionBehavior -EmptyMessage "No session behavior notes were collected."
        $sessionFlow = New-PivotDiagramHtml -Title "Session Control Review Path" -Steps @("Session context", "Managed state", "CA App Control", "Restrictions", "Response workflow")
        $oauthItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.OAuthActivity -EmptyMessage "No OAuth or app activity was collected."
        $oauthFlow = New-PivotDiagramHtml -Title "OAuth / App Review Path" -Steps @("Consent grant", "Client app", "Scopes", "Business need", "Governance review")
        $alertItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Alerts -EmptyMessage "No XDR alerts were matched."
        $xdrFlow = New-PivotDiagramHtml -Title "XDR Correlation Path" -Steps @("Alert/incident", "Entities", "Evidence", "Timeline", "Response decision")
        $incidentItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Incidents -EmptyMessage "No XDR incidents were matched."
        $endpointItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.EndpointContext -EmptyMessage "No endpoint context was collected."
        $endpointFlow = New-PivotDiagramHtml -Title "Endpoint Pivot Path" -Steps @("Device identity", "Logged-on user", "Alerts", "Process/network", "Containment review")
        $emailItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.EmailContext -EmptyMessage "No email context was collected."
        $emailFlow = New-PivotDiagramHtml -Title "Email / Phishing Pivot Path" -Steps @("Inbound message", "URL/attachment", "User action", "Authentication", "Post-auth behavior")
        $urlClickItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.UrlClickContext -EmptyMessage "No URL click context was collected."
        $cloudAppEventItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.CloudAppEvents -EmptyMessage "No CloudAppEvents were collected."
        $timelineItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.UnifiedTimeline -EmptyMessage "No unified timeline items were generated."
        $sourceHealthItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.SourceHealth -EmptyMessage "No source health diagnostics were captured."
        $dlpItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.DlpVisibility -EmptyMessage "No DLP visibility notes were collected."
        $riskItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.ObservedRisks -EmptyMessage "No observed risk indicators were generated."
        $gapItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.PotentialGaps -EmptyMessage "No potential gaps were generated."
        $recommendationItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.Recommendations -EmptyMessage "No recommendations were generated."
        $pivotItems = ConvertTo-ReportCardsHtml -Items $Script:Investigation.InvestigationPivots -EmptyMessage "No investigation pivots were generated."
        $overallPivotFlow = New-PivotDiagramHtml -Title "Recommended Investigation Pivot Flow" -Steps @("Identity", "Authentication", "Email/URL", "Endpoint/XDR", "Cloud activity", "Gaps & recommendations")

        $html = @"
<!DOCTYPE html>
<html>
<head>
<title>Shadow Trace Ops Investigation Report</title>
<style>
body {
    font-family: Segoe UI, Arial, sans-serif;
    background: radial-gradient(circle at top, #241633 0%, #121218 42%, #07070b 100%);
    color: #ebebf0;
    margin: 0;
    padding: 28px;
}
.report-shell {
    max-width: 1400px;
    margin: 0 auto;
}
.hero {
    position: relative;
    background: linear-gradient(135deg, rgba(28,28,36,.98), rgba(13,13,20,.98));
    border: 1px solid #503e62;
    border-left: 6px solid #b784ff;
    border-radius: 18px;
    padding: 28px 32px;
    box-shadow: 0 0 34px rgba(183,132,255,.22);
    overflow: hidden;
}
.hero:before {
    content: "";
    position: absolute;
    inset: -80px -120px auto auto;
    width: 300px;
    height: 300px;
    background: radial-gradient(circle, rgba(183,132,255,.35), transparent 65%);
}
.hero-content {
    position: relative;
    z-index: 2;
    min-height: 132px;
}
.brand-block {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 24px;
}
.brand-text h1 {
    color: #f4efff;
    margin: 0 0 6px 0;
    font-size: 42px;
    letter-spacing: .5px;
}
.brand-text .ops {
    color: #b784ff;
}
.subtitle {
    color: #cfc7dc;
    font-size: 16px;
    margin-bottom: 18px;
}
.logo-stack {
    display: flex;
    align-items: center;
    gap: 18px;
}
.tool-logo {
    max-width: 128px;
    max-height: 128px;
    border-radius: 16px;
    filter: drop-shadow(0 0 18px rgba(183,132,255,.45));
}
.tenant-logo {
    max-width: 120px;
    max-height: 80px;
    object-fit: contain;
    background: rgba(255,255,255,.06);
    border: 1px solid #503e62;
    border-radius: 12px;
    padding: 10px;
}
.tenant-logo-placeholder {
    width: 120px;
    height: 80px;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    color: #8f86a3;
    background: rgba(255,255,255,.04);
    border: 1px dashed #503e62;
    border-radius: 12px;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 1px;
}
.meta-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(260px, 1fr));
    gap: 8px 24px;
    margin-top: 8px;
    color: #d6d6de;
}
.meta-grid div span {
    color: #b784ff;
    font-weight: 700;
}
.badge-row {
    margin-top: 18px;
}
.badge {
    display: inline-block;
    padding: 6px 10px;
    background: #2e2638;
    border: 1px solid #503e62;
    color: #f5f5f5;
    border-radius: 999px;
    margin-right: 8px;
    font-size: 12px;
}
.metric-grid {
    display: grid;
    grid-template-columns: repeat(6, minmax(120px, 1fr));
    gap: 14px;
    margin: 22px 0;
}
.metric-card {
    background: linear-gradient(180deg, #21182d, #15151d);
    border: 1px solid #503e62;
    border-radius: 14px;
    padding: 18px 12px;
    text-align: center;
    box-shadow: 0 0 18px rgba(0,0,0,.28);
}
.metric-icon {
    color: #b784ff;
    font-size: 22px;
    margin-bottom: 8px;
}
.metric-value {
    font-size: 30px;
    font-weight: 800;
    color: #ffffff;
}
.metric-label {
    color: #cfc7dc;
    font-size: 12px;
    margin-top: 4px;
}
h2 {
    color: #caa2ff;
    margin-top: 0;
    letter-spacing: .2px;
}
a {
    color: #caa2ff;
}
.section {
    background: rgba(28,28,36,.96);
    border: 1px solid #3f3150;
    border-left: 5px solid #b784ff;
    border-radius: 14px;
    padding: 18px 20px;
    margin-bottom: 18px;
    box-shadow: 0 1px 10px rgba(0,0,0,.35);
}
.report-card-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 10px;
    margin-top: 10px;
}
.report-card {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    background: rgba(15,15,23,.78);
    border: 1px solid #3f3150;
    border-radius: 12px;
    padding: 12px 14px;
}
.card-dot {
    width: 9px;
    height: 9px;
    min-width: 9px;
    margin-top: 7px;
    border-radius: 50%;
    background: #b784ff;
    box-shadow: 0 0 10px rgba(183,132,255,.8);
}
.card-text {
    color: #e7e2f2;
    line-height: 1.45;
    font-size: 13px;
}
.muted-card {
    opacity: .72;
}
.empty-state {
    color: #a9a1b8;
    background: rgba(255,255,255,.03);
    border: 1px dashed #503e62;
    border-radius: 12px;
    padding: 12px 14px;
}
.pivot-diagram {
    margin-top: 16px;
    padding: 14px;
    border: 1px solid #3f3150;
    border-radius: 14px;
    background: linear-gradient(90deg, rgba(43,24,61,.7), rgba(12,12,18,.74));
}
.pivot-title {
    color: #caa2ff;
    font-weight: 800;
    text-transform: uppercase;
    font-size: 12px;
    letter-spacing: .8px;
    margin-bottom: 12px;
}
.flow-row {
    display: flex;
    align-items: stretch;
    gap: 8px;
    flex-wrap: wrap;
}
.flow-step {
    flex: 1;
    min-width: 130px;
    background: rgba(11,11,17,.72);
    border: 1px solid #503e62;
    border-radius: 12px;
    padding: 10px;
    text-align: center;
}
.flow-number {
    width: 26px;
    height: 26px;
    border-radius: 50%;
    margin: 0 auto 7px auto;
    background: #b784ff;
    color: #101018;
    font-weight: 900;
    line-height: 26px;
}
.flow-text {
    color: #f1edf8;
    font-size: 12px;
    line-height: 1.3;
}
.flow-arrow {
    color: #b784ff;
    font-size: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
}
.section-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 18px;
}
.priority {
    display: inline-block;
    padding: 9px 12px;
    background: #332b1a;
    border: 1px solid #d6a800;
    color: #ffdf7e;
    border-radius: 8px;
    font-weight: bold;
}
li {
    margin-bottom: 7px;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin-top: 8px;
    overflow: hidden;
    border-radius: 10px;
}
th {
    text-align: left;
    width: 260px;
    background: #24242e;
    color: #caa2ff;
    border: 1px solid #503e62;
    padding: 9px;
}
td {
    border: 1px solid #503e62;
    padding: 9px;
    color: #ebebf0;
}
.footer {
    color: #b4b4be;
    font-size: 12px;
    margin-top: 24px;
    display: flex;
    justify-content: space-between;
    border-top: 1px solid #3f3150;
    padding-top: 16px;
}
</style>
</head>
<body>
<div class="report-shell">

<div class="hero">
  <div class="hero-content">
    <div class="brand-block">
      <div class="brand-text">
        <h1>SHADOW TRACE <span class="ops">OPS</span></h1>
        <div class="subtitle">Post-authentication investigation, XDR correlation, and defensive gap assessment</div>
        <div class="meta-grid">
          <div><span>Generated:</span> $(Get-Date)</div>
          <div><span>Investigator:</span> $env:USERNAME</div>
          <div><span>Target User:</span> $upn</div>
          <div><span>Lookback:</span> $($Script:Investigation.AuthLookbackDays) day(s)</div>
          <div><span>Toolkit Phase:</span> $($Script:Investigation.ToolkitPhase)</div>
          <div><span>Run ID:</span> $($Script:Investigation.RunId)</div>
        </div>
        <div class="badge-row">
          <span class="badge">Read-only</span>
          <span class="badge">Advisory</span>
          <span class="badge">Post-authentication</span>
          <span class="badge">Advanced Hunting</span>
          <span class="badge">Source Health</span>
        </div>
      </div>
      <div class="logo-stack">
        $tenantLogoHtml
        $logoHtml
      </div>
    </div>
  </div>
</div>

$metricCardsHtml
$executiveFlow

<div class="section">
<h2>User Summary</h2>
<p>This Phase 1 report summarizes post-authentication activity review areas and potential defensive gaps for the selected user. Findings are advisory and should be validated by an analyst.</p>
$userSummaryTable
</div>

<div class="section">
<h2>Investigation Priority</h2>
<p class="priority">$($Script:Investigation.Priority)</p>
</div>

<div class="section">
<h2>Collection Status</h2>
<p>This section shows which collectors completed, failed, were skipped, or were not started.</p>
$collectionStatusTable
</div>

<div class="section">
<h2>Source Health and Query Diagnostics</h2>
<p>This section records Advanced Hunting source health, query duration, rows returned, and failure classification where available.</p>
$sourceHealthItems
</div>

<div class="section">
<h2>Identity Risk Summary</h2>
$identityRiskItems
$identityFlow
</div>

<div class="section">
<h2>Authentication Context</h2>
$authenticationItems
$authFlow
</div>

<div class="section">
<h2>Cloud Activity Timeline</h2>
$cloudActivityItems
$cloudFlow
</div>

<div class="section">
<h2>Session Behavior</h2>
$sessionBehaviorItems
$sessionFlow
</div>

<div class="section">
<h2>OAuth and Application Activity</h2>
$oauthItems
$oauthFlow
</div>

<div class="section">
<h2>Alerts and Detections</h2>
$alertItems
$xdrFlow
</div>

<div class="section">
<h2>Incidents</h2>
$incidentItems
$xdrFlow
</div>

<div class="section">
<h2>Defender for Endpoint Context</h2>
$endpointItems
$endpointFlow
</div>

<div class="section">
<h2>Defender for Office 365 / Email Context</h2>
$emailItems
$emailFlow
</div>

<div class="section">
<h2>Defender for Office 365 / URL Click Context</h2>
$urlClickItems
$emailFlow
</div>

<div class="section">
<h2>Defender for Cloud Apps / Cloud App Events</h2>
$cloudAppEventItems
$cloudFlow
</div>

<div class="section">
<h2>Unified Investigation Timeline</h2>
$timelineItems
$overallPivotFlow
</div>

<div class="section">
<h2>DLP and Data Movement Visibility</h2>
$dlpItems
</div>

<div class="section">
<h2>Observed Risk Indicators</h2>
$riskItems
</div>

<div class="section">
<h2>Potential Defensive Gaps</h2>
$gapItems
</div>

<div class="section">
<h2>Suggested Defensive Improvements</h2>
$recommendationItems
</div>

<div class="section">
<h2>Recommended Investigation Pivots</h2>
$pivotItems
$overallPivotFlow
</div>

<div class="footer">
<span>Shadow Trace Ops · Investigate. Correlate. Protect.</span>
<span>This report is read-only and advisory. It does not confirm compromise or perform remediation.</span>
</div>

</div>
</body>
</html>
"@

        $html | Out-File -FilePath $reportFile -Encoding UTF8
        $Script:CurrentReportFile = $reportFile
        Set-CollectionStatus -Name "ReportExport" -Status "Completed"

        Write-ToolLog "HTML summary report exported: $reportFile" "SUCCESS"
        $detailReport = Export-DetailedWorkflowReport -SummaryReportPath $reportFile

        Start-Process $reportFile
        if ($detailReport -and (Test-Path $detailReport)) {
            Start-Process $detailReport
        }
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
[void]$Script:cmbRunMode.Items.Add("Standard")
[void]$Script:cmbRunMode.Items.Add("Expanded")
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

$Script:chkIdentity = New-Object System.Windows.Forms.CheckBox
$Script:chkIdentity.Text = "Entra ID user risk and sign-in risk"
$Script:chkIdentity.Location = New-Object System.Drawing.Point(25, 280)
$Script:chkIdentity.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkIdentity.Checked = $true
$Script:chkIdentity.BackColor = $Script:Theme.FormBack
$Script:chkIdentity.ForeColor = $Script:Theme.TextFore
$Script:chkIdentity.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkIdentity)

$Script:chkAuthentication = New-Object System.Windows.Forms.CheckBox
$Script:chkAuthentication.Text = "Authentication context and Conditional Access result"
$Script:chkAuthentication.Location = New-Object System.Drawing.Point(25, 310)
$Script:chkAuthentication.Size = New-Object System.Drawing.Size(380, 24)
$Script:chkAuthentication.Checked = $true
$Script:chkAuthentication.BackColor = $Script:Theme.FormBack
$Script:chkAuthentication.ForeColor = $Script:Theme.TextFore
$Script:chkAuthentication.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkAuthentication)

$Script:chkCloud = New-Object System.Windows.Forms.CheckBox
$Script:chkCloud.Text = "Defender for Cloud Apps activity"
$Script:chkCloud.Location = New-Object System.Drawing.Point(25, 340)
$Script:chkCloud.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkCloud.Checked = $true
$Script:chkCloud.BackColor = $Script:Theme.FormBack
$Script:chkCloud.ForeColor = $Script:Theme.TextFore
$Script:chkCloud.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkCloud)

$Script:chkSession = New-Object System.Windows.Forms.CheckBox
$Script:chkSession.Text = "Session behavior and unmanaged device access"
$Script:chkSession.Location = New-Object System.Drawing.Point(25, 370)
$Script:chkSession.Size = New-Object System.Drawing.Size(380, 24)
$Script:chkSession.Checked = $true
$Script:chkSession.BackColor = $Script:Theme.FormBack
$Script:chkSession.ForeColor = $Script:Theme.TextFore
$Script:chkSession.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkSession)

$Script:chkOAuth = New-Object System.Windows.Forms.CheckBox
$Script:chkOAuth.Text = "OAuth and application activity"
$Script:chkOAuth.Location = New-Object System.Drawing.Point(450, 280)
$Script:chkOAuth.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkOAuth.Checked = $true
$Script:chkOAuth.BackColor = $Script:Theme.FormBack
$Script:chkOAuth.ForeColor = $Script:Theme.TextFore
$Script:chkOAuth.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkOAuth)

$Script:chkAlerts = New-Object System.Windows.Forms.CheckBox
$Script:chkAlerts.Text = "Defender XDR alerts and detections"
$Script:chkAlerts.Location = New-Object System.Drawing.Point(450, 310)
$Script:chkAlerts.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkAlerts.Checked = $true
$Script:chkAlerts.BackColor = $Script:Theme.FormBack
$Script:chkAlerts.ForeColor = $Script:Theme.TextFore
$Script:chkAlerts.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkAlerts)

$Script:chkDlp = New-Object System.Windows.Forms.CheckBox
$Script:chkDlp.Text = "DLP and data movement visibility"
$Script:chkDlp.Location = New-Object System.Drawing.Point(450, 340)
$Script:chkDlp.Size = New-Object System.Drawing.Size(340, 24)
$Script:chkDlp.Checked = $true
$Script:chkDlp.BackColor = $Script:Theme.FormBack
$Script:chkDlp.ForeColor = $Script:Theme.TextFore
$Script:chkDlp.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$form.Controls.Add($Script:chkDlp)

# Authentication log drilldown selector moved to the Investigation Target row for better visibility.

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

$btnJsonExport = New-Button "Export JSON Snapshot" 380 512 { Export-InvestigationJson }
$form.Controls.Add($btnJsonExport)

$btnClearLog = New-Button "Clear Log View" 560 512 { Clear-InvestigationLog }
$form.Controls.Add($btnClearLog)

$btnExit = New-Button "Exit" 740 512 { $form.Close() }
$form.Controls.Add($btnExit)

$Script:txtLog = New-Object System.Windows.Forms.TextBox
$Script:txtLog.Location = New-Object System.Drawing.Point(20, 575)
$Script:txtLog.Size = New-Object System.Drawing.Size(1070, 280)
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

[void]$form.ShowDialog()
