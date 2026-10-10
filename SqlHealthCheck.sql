/*
    SQL Server Health Check
    -----------------------
    Run in SQL Server Management Studio (SSMS) after the PowerShell checks pass.
    The PowerShell script answers "can a client reach SQL Server?"
    These queries answer "is the instance itself healthy?"

    Read-only: nothing here changes data or settings.
    Requires: VIEW SERVER STATE permission (sysadmin has it).
*/

-- 1. Instance details and authentication mode
--    "Windows only" means SQL logins (like 'sa') will be rejected,
--    a common cause of "Login failed for user" errors.
SELECT
    SERVERPROPERTY('MachineName')                    AS MachineName,
    ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER (default)') AS InstanceName,
    SERVERPROPERTY('Edition')                        AS Edition,
    SERVERPROPERTY('ProductVersion')                 AS ProductVersion,
    SERVERPROPERTY('ProductLevel')                   AS ProductLevel,
    CASE SERVERPROPERTY('IsIntegratedSecurityOnly')
        WHEN 1 THEN 'Windows only'
        ELSE 'Mixed (Windows + SQL logins)'
    END                                              AS AuthenticationMode;

-- 2. Uptime: a very recent start time can explain dropped connections
SELECT
    sqlserver_start_time                                 AS StartTime,
    DATEDIFF(HOUR, sqlserver_start_time, SYSDATETIME())  AS UptimeHours
FROM sys.dm_os_sys_info;

-- 3. Which IP addresses and ports SQL Server is listening on
--    Should match the port the PowerShell script found.
SELECT
    ip_address,
    port,
    type_desc,
    state_desc
FROM sys.dm_tcp_listener_states
WHERE type_desc = 'TSQL';

-- 4. How this session connected (TCP vs. shared memory, NTLM vs. Kerberos)
SELECT
    net_transport   AS Transport,
    auth_scheme     AS AuthScheme,
    local_tcp_port  AS ServerPort,
    client_net_address AS ClientAddress
FROM sys.dm_exec_connections
WHERE session_id = @@SPID;

-- 5. Database state and recovery model
--    Anything not ONLINE, or not MULTI_USER, will block application logins.
SELECT
    name                 AS DatabaseName,
    state_desc           AS State,
    user_access_desc     AS UserAccess,
    recovery_model_desc  AS RecoveryModel
FROM sys.databases
ORDER BY name;

-- 6. Most recent backup of each database
--    NULL means no backup has ever been recorded.
SELECT
    d.name AS DatabaseName,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDifferentialBackup,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
    ON b.database_name = d.name
WHERE d.name <> 'tempdb'
GROUP BY d.name
ORDER BY d.name;

-- 7. Who is connected right now, and from which application
SELECT
    login_name    AS LoginName,
    host_name     AS HostName,
    program_name  AS ProgramName,
    COUNT(*)      AS Sessions
FROM sys.dm_exec_sessions
WHERE is_user_process = 1
GROUP BY login_name, host_name, program_name
ORDER BY Sessions DESC;
