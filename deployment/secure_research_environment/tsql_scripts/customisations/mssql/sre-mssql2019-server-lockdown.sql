PRINT '2.1 - Ensure Ad Hoc Distributed Queries Server Configuration Option is set to 0'
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'Ad Hoc Distributed Queries', 0;
RECONFIGURE;
GO

EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.2 - Ensure CLR Enabled Server Configuration Option is set to 0'
EXECUTE sp_configure 'clr enabled', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.3 - Ensure Cross DB Ownership Chaining Server Configuration Option is set to 0'
EXECUTE sp_configure 'cross db ownership chaining', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.4 - Ensure Database Mail XPs Server Configuration Option is set to 0'
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'Database Mail XPs', 0;
RECONFIGURE;
GO

EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.5 - Ensure Ole Automation Procedures Server Configuration Option is set to 0'
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'Ole Automation Procedures', 0;
RECONFIGURE;
GO

EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.6 - Ensure Remote Access Server Configuration Option is set to 0'
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'remote access', 0;
RECONFIGURE;
GO

EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.7 - Ensure Remote Admin Connections Server Configuration Option is set to 0'
EXECUTE sp_configure 'remote admin connections', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.8 - Ensure Scan For Startup Procs Server Configuration Option is set to 0'
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'scan for startup procs', 0;
RECONFIGURE;
GO

EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '2.9 - Ensure Trustworthy Database Property is set to Off'
ALTER DATABASE master SET TRUSTWORTHY OFF;
GO

PRINT ''
PRINT '2.12 - Ensure Hide Instance option is set to Yes for Production SQL Server instances'
EXEC master.sys.xp_instance_regwrite @rootkey = N'HKEY_LOCAL_MACHINE', @key = N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib', @value_name = N'HideInstance', @type = N'REG_DWORD', @value = 1;
GO

PRINT ''
PRINT '5.1 - Ensure Maximum number of error log files is set to greater than or equal to 12'
EXEC master.sys.xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs', REG_DWORD, 14;
GO

PRINT ''
PRINT '5.2 - Ensure Default Trace Enabled Server Configuration Option is set to 1'
EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE;
EXECUTE sp_configure 'default trace enabled', 1;
RECONFIGURE;
GO

EXECUTE sp_configure 'show advanced options', 0;
RECONFIGURE;
GO

PRINT ''
PRINT '5.3 - Ensure Login Auditing is set to failed logins'
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'AuditLevel', REG_DWORD, 2
GO