# Set execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

pip install --upgrade certifi

$certifiPath = python -m certifi
[Environment]::SetEnvironmentVariable("SSL_CERT_FILE", $certifiPath, "Machine")
[Environment]::SetEnvironmentVariable("SSL_CERT_FILE", $certifiPath, "User")
