Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted; # Set PSGallery as trusted - to avoid untrusted prompt

Install-Module -Name Microsoft.Graph.Applications, Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions -Confirm:$false