# SQL Server Connectivity Checker

A PowerShell and T-SQL toolkit that diagnoses the most common reasons an application can't connect to SQL Server, then confirms the instance itself is healthy.

> **Scenario:** Tremols Tech, an early-stage Managed Service Provider (MSP), supports **ClearView Dental Associates**, a fictional dental group with multiple clinics and ~180 staff. After a server restart, ClearView's imaging application can no longer connect to its SQL Server database, and clinics can't pull up patient images. This toolkit finds the cause in seconds instead of a manual check across five different consoles. ClearView and all names in this repo are fictional.

## 📊 Progress

| # | Check | Tool | Status |
| - | ----- | ---- | ------ |
| 01 | SQL Server service running | PowerShell | ✅ Complete |
| 02 | SQL Browser service (named instances) | PowerShell | ✅ Complete |
| 03 | TCP/IP enabled and port detection | PowerShell | ✅ Complete |
| 04 | Port listening | PowerShell | ✅ Complete |
| 05 | Windows Firewall inbound rule | PowerShell | ✅ Complete |
| 06 | Login test (`SELECT @@VERSION`) | PowerShell + .NET | ✅ Complete |
| 07 | Instance health queries | T-SQL | ✅ Complete |
| 08 | Remote checks with `Invoke-Command` | PowerShell | 🔜 Planned |
| 09 | Export results to CSV for ticket notes | PowerShell | 🔜 Planned |

## 🗄️ What each check covers

**Part 1: Can a client reach SQL Server?** (`Test-SqlConnectivity.ps1`)

- **SQL Server service:** confirms `MSSQLSERVER` or `MSSQL$<instance>` is running
- **SQL Browser:** confirms named instances can be found by clients (UDP 1434)
- **TCP/IP and port:** reads SQL Server's network settings from the registry, flags disabled TCP/IP (the default on SQL Server Express) and dynamic ports that can change after a restart
- **Port listening:** confirms SQL Server is actually listening on the configured port
- **Firewall:** looks for an enabled inbound allow rule, the most common cause of "works on the server, fails from the clinic PCs"
- **Login test:** opens a Windows-authenticated connection and runs a query

###### Outcome: a PASS / WARN / FAIL report with the exact fix for each failed check.

**Part 2: Is the instance healthy?** (`sql/SqlHealthCheck.sql`)

- Edition, version, and authentication mode (Windows only vs. mixed)
- Uptime since the last restart
- Listening IP addresses and ports, and how the current session connected
- Database state, user access mode, and recovery model
- Most recent full, differential, and log backup for each database
- Active sessions by login, host, and application

###### Outcome: a read-only snapshot of instance health to confirm the fix and document the ticket.

## 🚀 Usage

**PowerShell checks** (run on the SQL Server machine, Windows PowerShell 5.1 or PowerShell 7):

```powershell
# Default instance
.\Test-SqlConnectivity.ps1

# Named instance, for example SQL Server Express
.\Test-SqlConnectivity.ps1 -InstanceName SQLEXPRESS

# Include a Windows-authenticated login test
.\Test-SqlConnectivity.ps1 -InstanceName SQLEXPRESS -TestLogin
```

If script execution is blocked, allow it for the current window only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

**T-SQL health check:** open `sql/SqlHealthCheck.sql` in SQL Server Management Studio (SSMS), connect to the instance, and run it.

## 🖥️ Example output

**Healthy instance: all checks pass**

![Healthy instance](screenshots/healthy.png)

**SQL Server service stopped: the script flags the service and the closed port**

![Service stopped](screenshots/service-stopped.png)

**T-SQL health check results in SSMS**

![SQL health check](screenshots/sql-health-check.png)

## 🔧 How the project is structured

```
SQL-Server-Connectivity-Checker/
├── Test-SqlConnectivity.ps1   # PowerShell connectivity checks
├── sql/
│   └── SqlHealthCheck.sql     # Read-only T-SQL health queries
├── screenshots/               # Example output
└── README.md
```

## 🎯 Project Objectives

By completing this project I will:

- Turn a manual troubleshooting process I use in application support into a repeatable script
- Practice PowerShell for Windows service, registry, network, and firewall checks
- Write read-only T-SQL against system views (`sys.databases`, `sys.dm_exec_sessions`, `msdb.dbo.backupset`)
- Reduce time to root cause for database connectivity incidents
- Build a documented portfolio of practical infrastructure work

## 🛠️ Technologies & Tools

- PowerShell · T-SQL · Microsoft SQL Server 2022 Express · SQL Server Management Studio (SSMS) · SQL Server Configuration Manager · Windows Firewall · Windows Registry · .NET SqlClient

## 👤 About

Built by **Charles Tremols** to automate SQL Server troubleshooting I perform in application support.

- 💼 [LinkedIn: Charles Tremols](https://www.linkedin.com/in/charles-tremols/)
- 📧 <cjtremols@proton.me>

###### This is a personal project built and tested in my own lab environment. No production, employer, or customer systems or data were used.
