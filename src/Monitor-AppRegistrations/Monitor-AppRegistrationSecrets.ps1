<#
.SYNOPSIS
  Get the details of App Registrations with an expired secret or certificate
.DESCRIPTION
  This script is intended to run as part of an Azure Automation. 
  This script will scan through all the Application Registrations in an Azure Tenancy and
  identify the Applications with expired secrets or certificates.
.PARAMETER <Parameter_Name>
    <Brief description of parameter input required. Repeat this attribute if required>
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  <Outputs if any, otherwise state None - example: Log file stored in C:\Windows\Temp\<name>.log>
.NOTES
  FileName:         Monitor-AppRegistrationSecrets.ps1
  Version:          1.0
  Author:           Ebby Peter
  Creation Date:    01/2024
  Purpose/Change:   Initial script development
  
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
#>

#------------------------------[Script Parameters]------------------------------
[CmdletBinding()]
param (
  [switch]
  $RunAsRunbook
)

#-------------------------------[Initialisations]-------------------------------
# Import Modules & Snap-ins
Import-Module Microsoft.Graph.Applications;
Import-Module Microsoft.Graph.Authentication;
Import-Module Microsoft.Graph.Users.Actions;

# Initialise Variables
$sendEmails = $true; #When true, will send email notification
$warnDays = 28; #Add an App Registration to the report if the password has less than this number of days to expiry

if($RunAsRunbook){
  Connect-MgGraph `
    -Scopes "Application.Read.All, Mail.Send, User.Read.All"
    -Identity `
    -NoWelcome

    # Load Configuration variables from Automation Account Variables
    $sendEmails = $true;
    $warnDays = Get-AutomationVariable -Name "warnDays"
    $mailRecipients = Get-AutomationVariable -Name "mailRecipients"
    $mailSender = Get-AutomationVariable -Name "mailSender"
} else {
  Connect-MgGraph `
    -Scopes "Application.Read.All, Mail.Send, User.Read.All" `
    -NoWelcome;
    $sendEmails = $false;
    $mailRecipients = "ebby@chackunkal.com"
    $mailSender = "ebby@chackunkal.com"
}

#---------------------------------[Declarations]--------------------------------
$now = Get-Date;

#----------------------------------[Functions]----------------------------------
Function Get-AppsWithExpiredSecretOrCert{
  <#
  .SYNOPSIS
    Reviews all Application Registations and get the list applications with
    expired or soon to be expired secrets & certificates.
  .INPUTS
    - warningDays: An integer that denotes if the password/cert has less than this number of days to expiry
  .OUTPUTS
    - An array of objects that represent the Application Registations that need attention.
      The object will contain the following properties
        * Level = 'Critical' | 'Warning'
        * AppType = 'AppRegistration'
        * CredentialType = 'Secret' | 'Certificate'
        * Name = <Application Name>
        * ProblemText = <Text explaining the issue>
        * ExpiryDate = <Credential expiry date>
  #>
  Param(
    [Parameter(Mandatory = $true)]
    [int]$warningDays
  )

  Begin{
    Write-Verbose -Message "Getting application details from Entra Id";
    $apps = Get-MgApplication -All;
    Write-Verbose -Message "Retrieved $($apps.Count) Apps."
  }

  Process{
    $problems = @();
    # Review each app
    $apps | ForEach-Object{
      $app = $_;

      # Review App Registration secrets
      if ($app.PasswordCredentials.Count -ge 1){
        # Get the latest secret in case there are multiple secret entries
        $latestPassword = $app.PasswordCredentials `
          | Sort-Object -Property EndDateTime -Descending `
          | Select-Object -first 1;
        $latestPasswordExpiresInDays = ($latestPassword.EndDateTime - $now).days;

        if ($latestPasswordExpiresInDays -lt 0) {
          # Secret already expired
          $props = [ordered]@{
            Level = 'Critical'
            AppType = 'AppRegistration'
            CredentialType = 'Secret'
            Name = $app.DisplayName
            ProblemText = "Latest Password Already Expired $(0 - $latestPasswordExpiresInDays) days ago"
            ExpiryDate = $latestpassword.EndDateTime
          }
          $problems += New-Object -TypeName PSCustomObject -Property $props;
        } elseif ($latestPasswordExpiresInDays -lt $warningDays) {
          # Secret will expire soon
          $props = [ordered]@{
            Level = 'Warning'
            AppType = 'AppRegistration'
            CredentialType = 'Secret'
            Name = $app.DisplayName
            ProblemText = "Latest Password Expires in $latestPasswordExpiresInDays days"
            ExpiryDate = $latestpassword.EndDateTime
          }
          $problems += New-Object -TypeName PSCustomObject -Property $props;
        }
      }
      
      # Review App Registation Certificates
      if($app.KeyCredentials.Count -ge 1){
        # Get the latest cert
        $latestCert = $app.KeyCredentials `
          | Sort-Object -Property EndDateTime -Descending `
          | Select-Object -first 1;
        $latestCertExpiresInDays = ($latestCert.EndDateTime - $now).days

        if ($latestCertExpiresInDays -lt 0) {
          # Certificate already expired
          $props = [ordered]@{
            Level = 'Critical'
            AppType = 'AppRegistration'
            CredentialType = 'Certificate'
            Name = $app.DisplayName
            ProblemText = "Latest Cert Already Expired $(0 - $latestCertExpiresInDays) days ago"
            ExpiryDate = $latestCert.EndDateTime
          }
          $problems += New-Object -TypeName PSCustomObject -Property $props
        } elseif ($latestCertExpiresInDays -lt $warningDays) {
          # Certificate will expire soon
          $props = [ordered]@{
            Level = 'Warning'
            AppType = 'AppRegistration'
            CredentialType = 'Certificate'
            Name = $app.DisplayName
            ProblemText = "Latest Cert Expires in $latestCertExpiresInDays days"
            ExpiryDate = $latestCert.EndDateTime
          }
          $problems += New-Object -TypeName PSCustomObject -Property $props
        }
      }
    }

    Write-Verbose -Message "Application Registations with issues : $($problems.Count)";
  }

  End{
    return $problems;
  }
}

Function Format-MessageData {
  <#
  .SYNOPSIS
      Compiles data into the right format for Send-MgUserMessage to receive
  .NOTES
      Currently only builds HTML Emails
      Does not handle attachments (yet...)
  .LINK
      
  .EXAMPLE
      Format-MessageData -Recipients 'firstname.lastname@blah.co.nz', 'second.person@blah.co.nz' -subject "Hello" -Body "Well Hello there"
  #> 
  Param (
      [string[]] $Recipients,
      [string[]] $CCRecipients,
      [string]   $From,
      [string]   $Body,
      [string]   $Subject,
      [switch]   $DontSaveToSentItems
  )

  Begin{
  }
  
  Process{
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

  End{
  }
  
}

function Send-ReportAsEmail {
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

  $mailbody = @'
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
'@;
    $mailbody += '<H3>App registrations detected with Secrets that are going to or have already expired</H3>'
    $mailbody += "<P>We have detected a total of {0} issues, made up of: <BR />{1} Secrets already expired<BR />{2} Secrets Expiring within the next $warndays days </P>" -f `
                    ($problems | Measure-Object).count,
                    ($problems | Where-Object {$_.level -eq 'Critical'} | Measure-Object).count,
                    ($problems | Where-Object {$_.level -eq 'Warning'} | Measure-Object).count
    $mailbody += $problems | Sort-Object -Property ExpiryDate | ConvertTo-Html -Fragment

    $messagedata = Format-MessageData -Recipients $MailRecipients -Body $mailbody -From $MailSender -Subject "App Registration Secrets Expiry Report" -DontSaveToSentItems
    Send-MgUserMail -BodyParameter $messagedata -UserId $mailSender 

    Write-Output $messagedata
  }
}

#----------------------------------[Execution]----------------------------------
$issues = Get-AppsWithExpiredSecretOrCert -warningDays $warnDays;
Write-Information -MessageData "App Registations with issues : $($issues.Count)";

if($sendEmails){
  Send-ReportAsEmail -problems $issues
}

# For testing only
Write-Output $issues;
