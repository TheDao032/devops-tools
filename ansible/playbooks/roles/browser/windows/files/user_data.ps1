# Set execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# Install WinRM if not enabled
winrm quickconfig -q
winrm set winrm/config/service '@{AllowUnencrypted="false"}'
winrm set winrm/config/service/auth '@{Basic="true"}'

# Create a self-signed certificate for WinRM HTTPS
$cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation Cert:\LocalMachine\My
$thumbprint = $cert.Thumbprint

# Remove any existing HTTPS listener
winrm delete winrm/config/Listener?Address=*+Transport=HTTPS 2>$null

# Create WinRM HTTPS listener
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"localhost`"; CertificateThumbprint=`"$thumbprint`"}"

# Allow inbound on port 5986
New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow

# Restart WinRM service
Restart-Service winrm
