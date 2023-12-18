#Requires -Modules Microsoft.Graph.Applications, Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions
#TODO: Adapt script to run in Automation Account using a Managed Identity
#TODO: Add feature to script - monitor for app registrations with less than 2 owners

[CmdletBinding()]
param (
    [switch]
    # When true, will attempt to connect to graph with a Managed Identity assigned to Automation Account, and send email as configured user
    $RunAsRunbook
)

if ($RunAsRunbook) {
    Connect-MgGraph -Identity -NoWelcome
} else {
    Connect-MgGraph -NoWelcome
}

#region     Configuration Variables
if ($runasrunbook) { #when running as runbook, load configuration variables from Automation Account Variables
    $warnDays = Get-AutomationVariable -Name "warnDays"
    $mailRecipients = Get-AutomationVariable -Name "mailRecipients"
    $mailSender = Get-AutomationVariable -Name "mailSender"
} else { #running locally here, so just load default values
    $warnDays = 28 # Add an App Registration to the report if the password has less than this number of days to expiry
    $mailRecipients = "ebby@techlabs.nz"
    $mailSender = "ebby@techlabs.nz"
}
$mailUserId = $mailSender
#endregion  Configuration Variables

#region      Helper Functions
function MGMailMessageData {
    <#
    .SYNOPSIS
        Compiles data into the right format for Send-MgUserMessage to receive
    .NOTES
        Currently only builds HTML Emails
        Does not handle attachments (yet...)
    .LINK
        
    .EXAMPLE
        MGMailMessageData -Recipients 'firstname.lastname@blah.co.nz', 'second.person@blah.co.nz' -subject "Hello" -Body "Well Hello there"
    #>
    #TODO: Add attachment handling.
    
    param (
        [string[]] $Recipients,
        [string[]] $CCRecipients,
        [string]   $From,
        [string]   $Body,
        [string]   $Subject,
        [switch]   $DontSaveToSentItems
    )
    $out = [ordered]@{}
    $out.Subject = $Subject
    $out.Body = @{
        ContentType = "HTML"
        Content = $Body
    }

    $out += @{ToRecipients =
        [array]((($Recipients).split(';').trim()) | ForEach-Object {
            @{
                emailAddress = @{address = $_}
            }
        })
    }

    if ($CCRecipients.count -ge 1) {
        $out += @{CCRecipients =
            [array]((($CCRecipients).split(';').trim())| ForEach-Object {
                @{
                    emailAddress = @{address = $_}
                }
            })
        }
    }

    if ($From) {
        $out += @{Sender = 
            @{emailAddress = @{address = $From}}
        }
    }
    @{
        Message = $out
        SaveToSentItems = !$DontSaveToSentItems
    }
}

function ComposeMailMessageData {
    <#
    .SYNOPSIS
        Compiles data into the right format for Send-MgUserMessage to receive
    .NOTES
        Currently only builds HTML Emails
        Does not handle attachments (yet...)
    .LINK
        
    .EXAMPLE
        MGMailMessageData -Recipients 'firstname.lastname@blah.co.nz', 'second.person@blah.co.nz' -subject "Hello" -Body "Well Hello there"
    #>
    
    param (
        $problems
    )
    if ($problems.count -ge 1) {
    Write-Output ("{0} problems found with App Registrations:" -f ($problems | Measure-Object).count)
    $problems | Sort-Object -Property ExpiryDate | Format-Table -AutoSize 

    $mailbody = @’
<HTML>
<HEAD>
<TITLE>App Registration passwords and secrets expiry report</TITLE>
<style>
body { font-family:Tahoma; font-size:10pt; }
td, th { border:1px solid black;border-collapse:collapse;}
th { color:white; background-color: #007fc4; }
table, tr, td, th { padding: 3px; margin: 0px; border-spacing: 0px }
table { margin-left:20px; }

</style>
</HEAD>
<BODY>
‘@
    $mailbody += '<H3>App registrations detected with Secrets that are going to or have already expired</H3>'
    $mailbody += "<P>We have detected a total of {0} issues, made up of: <BR />{1} Secrets already expired<BR />{2} Secrets Expiring within the next $warndays days </P>" -f `
                    ($problems | Measure-Object).count,
                    ($problems | Where-Object {$_.level -eq 'Critical'} | Measure-Object).count,
                    ($problems | Where-Object {$_.level -eq 'Warning'} | Measure-Object).count
    $mailbody += $problems | Sort-Object -Property ExpiryDate | ConvertTo-Html -Fragment

    $messagedata = MGMailMessageData -Recipients $MailRecipients -Body $mailbody -From $MailSender -Subject "App Registration Secrets Expiry Report" -DontSaveToSentItems
    Send-MgUserMail -BodyParameter $messagedata -UserId $mailUserId 
}
}
#endregion   Helper Functions



$apps = get-mgapplication -all
$now = get-date

$problems = @()
$apps | ForEach-Object {
    $app = $_

    # get latest password
    if ($app.PasswordCredentials.count -ge 1) {
        $latestPassword = $app.PasswordCredentials | Sort-Object -Property EndDateTime -Descending | Select-Object -first 1
        $latestPasswordExpiresInDays = ($latestPassword.EndDateTime - $now).days

        if ($latestPasswordExpiresInDays -lt 0) {
            $props = [ordered]@{
                level = 'Critical'
                AppType = 'AppRegistration'
                Name = $app.DisplayName
                ProblemText = "Latest Password Already Expired $(0 - $latestPasswordExpiresInDays) days ago"
                ExpiryDate = $latestpassword.EndDateTime
            }
            $problems += New-Object -TypeName PSCustomObject -Property $props
        } elseif ($latestPasswordExpiresInDays -lt $warnDays) {
            $props = [ordered]@{
                level = 'Warning'
                AppType = 'AppRegistration'
                Name = $app.DisplayName
                ProblemText = "Latest Password Expires in $latestPasswordExpiresInDays days"
                ExpiryDate = $latestpassword.EndDateTime
            }
            $problems += New-Object -TypeName PSCustomObject -Property $props
        }
    }

    if ($app.keyCredentials.count -ge 1) {
        $latestCert = $app.KeyCredentials | Sort-Object -Property EndDateTime -Descending | Select-Object -first 1
        $latestCertExpiresInDays = ($latestCert.EndDateTime - $now).days

        if ($latestCertExpiresInDays -lt 0) {
            $props = [ordered]@{
                level = 'Critical'
                AppType = 'AppRegistration'
                Name = $app.DisplayName
                ProblemText = "Latest Cert Already Expired $(0 - $latestCertExpiresInDays) days ago"
                ExpiryDate = $latestCert.EndDateTime
            }
            $problems += New-Object -TypeName PSCustomObject -Property $props
        } elseif ($latestCertExpiresInDays -lt 0) {
            $props = [ordered]@{
                level = 'Warning'
                AppType = 'AppRegistration'
                Name = $app.DisplayName
                ProblemText = "Latest Cert Already Expires in $latestCertExpiresInDays days"
                ExpiryDate = $latestCert.EndDateTime
            }
            $problems += New-Object -TypeName PSCustomObject -Property $props
        }

    }
    # get latest cert (aka key)
}

Write-Host "Problem Count :" $problems.Count;