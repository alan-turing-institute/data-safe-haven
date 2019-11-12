param(
  [Parameter(Position=0, HelpMessage = "Type of synchronisation ('Initial' or 'Delta')")]
  [ValidateSet("Initial", "Delta")]
  [String]
  $sync = "Initial"
)

Import-Module –Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync"
Start-ADSyncSyncCycle -PolicyType $sync