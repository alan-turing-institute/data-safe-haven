# Install features on Server

# Windows AD Domain Services

Install-windowsfeature -name AD-Domain-Services -IncludeManagementTools  

# Windows Update Services

Install-WindowsFeature -Name UpdateServices -IncludeManagementTools

# Run post WSUS configuration task

cmd /c "C:\Program Files\Update Services\Tools\WsusUtil.exe" PostInstall CONTENT_DIR=F:\WSUS