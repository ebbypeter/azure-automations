# Set PSGallery as trusted - to avoid untrusted prompt
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted; 
# Install Required modules
Install-Module `
    -Name Microsoft.Graph.Applications, Microsoft.Graph.Authentication, Microsoft.Graph.Users.Actions `
    -Confirm:$false