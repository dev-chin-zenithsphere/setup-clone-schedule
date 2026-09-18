# MSSQL Server Setup Guide

คู่มือนี้ใช้สำหรับเตรียม **Windows Server เครื่องใหม่** ให้เป็น Microsoft SQL Server
ปลายทางสำหรับระบบ Database Clone โดยตัวอย่างนี้ใช้ SQL Server Express instance
`SQLEXPRESS` และรับการเชื่อมต่อจากเครื่องอื่นผ่าน TCP `1433`

## 1. Network ที่ใช้ในตัวอย่าง

  รายการ                  ค่า
  ----------------------- ---------------------------------------
  Destination Server IP   `192.168.20.3`
  Subnet Mask             `255.255.255.0`
  SQL Instance            `SQLEXPRESS`
  TCP Port                `1433`
  Authentication          SQL Server and Windows Authentication
  SQL Login               `sa`
  Destination Database    `ajinomoto_jp_ipms`

ก่อนติดตั้ง SQL Server ให้ตรวจว่าเครื่องต้นทางมองเห็น Server ได้:

``` powershell
ping 192.168.20.3
```

> การ ping ได้ไม่ได้ยืนยันว่า SQL Server พร้อมใช้งาน แต่ช่วยยืนยันการเชื่อมต่อระดับ
> network เบื้องต้น

------------------------------------------------------------------------

## 2. ติดตั้ง SQL Server

ติดตั้ง Microsoft SQL Server รุ่นที่ต้องการ เช่น SQL Server Express

ระหว่างติดตั้ง:

-   เลือก Database Engine Services
-   ใช้ Named Instance: `SQLEXPRESS`
-   เพิ่ม Windows Administrator ปัจจุบันเป็น SQL Server administrator

หลังติดตั้งควรมี service:

``` text
SQL Server (SQLEXPRESS)
```

ตรวจด้วย PowerShell:

``` powershell
Get-Service 'MSSQL$SQLEXPRESS'
```

ควรเป็น:

``` text
Status : Running
```

------------------------------------------------------------------------

## 3. เชื่อมต่อ Local SQL Server ครั้งแรก

เปิด SQL Server Management Studio (SSMS) แล้วใช้:

``` text
Server Name:
.\SQLEXPRESS
```

หรือ:

``` text
JP-PMS-2\SQLEXPRESS
```

เลือก:

``` text
Authentication:
Windows Authentication
```

หากพบ SSL error:

``` text
The certificate chain was issued by an authority that is not trusted
```

ให้เปิด:

``` text
Trust Server Certificate: ✓
```

แล้ว Connect ใหม่

------------------------------------------------------------------------

## 4. เปิด Mixed Mode Authentication

เพื่อให้เครื่องอื่นเชื่อมด้วย `sa` ได้:

1.  เปิด SSMS
2.  คลิกขวาที่ Server
3.  เลือก **Properties**
4.  เลือก **Security**
5.  ที่ Server authentication เลือก:

``` text
SQL Server and Windows Authentication mode
```

6.  กด OK

ตรวจสอบด้วย SQL:

``` sql
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsOnly;
```

ผลที่ต้องการ:

``` text
0
```

`0` หมายถึง Mixed Mode เปิดใช้งานแล้ว

------------------------------------------------------------------------

## 5. เปิดใช้งาน `sa`

เปิด New Query ด้วย Windows Authentication:

``` sql
ALTER LOGIN [sa] ENABLE;
GO

ALTER LOGIN [sa]
WITH PASSWORD = '<STRONG_PASSWORD>';
GO
```

ตรวจสอบ:

``` sql
SELECT
    name,
    is_disabled
FROM sys.sql_logins
WHERE name = 'sa';
```

ผลที่ต้องการ:

``` text
name    is_disabled
sa      0
```

> อย่าเก็บรหัสผ่านจริงไว้ใน README หรือ Git repository ให้กำหนดผ่าน `.env` ที่ไม่ถูก
> commit

------------------------------------------------------------------------

## 6. Enable TCP/IP

เปิด:

``` text
SQL Server Configuration Manager
```

ไปที่:

``` text
SQL Server Network Configuration
└── Protocols for SQLEXPRESS
```

ตั้ง:

``` text
TCP/IP = Enabled
```

จากนั้นเปิด Properties ของ `TCP/IP` และเลือกแท็บ:

``` text
IP Addresses
```

เลื่อนไปที่ `IPAll`

ตั้ง:

``` text
TCP Dynamic Ports :
TCP Port          : 1433
```

**TCP Dynamic Ports ต้องเป็นช่องว่าง** หากมี `0` ให้ลบออก

กด Apply / OK

------------------------------------------------------------------------

## 7. Restart SQL Server

PowerShell แบบ Administrator:

``` powershell
Restart-Service 'MSSQL$SQLEXPRESS'
```

ตรวจ:

``` powershell
Get-Service 'MSSQL$SQLEXPRESS'
```

------------------------------------------------------------------------

## 8. ตรวจว่า SQL Server Listen Port 1433

บน Server:

``` powershell
netstat -ano | findstr :1433
```

หรือ:

``` powershell
Get-NetTCPConnection -LocalPort 1433 -State Listen
```

ควรพบลักษณะ:

``` text
TCP    0.0.0.0:1433    0.0.0.0:0    LISTENING
```

ถ้าไม่มี `LISTENING` อย่าเพิ่งตรวจเครื่อง Client ให้กลับไปตรวจ TCP/IP, IPAll และ
restart SQL Server

------------------------------------------------------------------------

## 9. เปิด Windows Firewall TCP 1433

เปิด PowerShell แบบ Administrator:

``` powershell
New-NetFirewallRule `
    -DisplayName "SQL Server TCP 1433" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 1433 `
    -Action Allow
```

ตรวจ rule:

``` powershell
Get-NetFirewallRule -DisplayName "SQL Server TCP 1433"
```

------------------------------------------------------------------------

## 10. ทดสอบจากเครื่อง Client

จากเครื่องต้นทาง:

``` powershell
Test-NetConnection 192.168.20.3 -Port 1433
```

ผลที่ต้องการ:

``` text
RemoteAddress    : 192.168.20.3
RemotePort       : 1433
TcpTestSucceeded : True
```

หาก:

``` text
PingSucceeded    : True
TcpTestSucceeded : False
```

ให้ตรวจ:

-   SQL Server TCP/IP Enabled หรือไม่
-   SQL Server Listen 1433 หรือไม่
-   Restart SQL Server แล้วหรือไม่
-   Windows Firewall เปิด TCP 1433 หรือไม่

------------------------------------------------------------------------

## 11. ทดสอบ SQL Authentication

จากเครื่อง Client ที่มี `sqlcmd`:

``` powershell
sqlcmd -S "tcp:192.168.20.3,1433" `
       -U sa `
       -P "<PASSWORD>" `
       -C `
       -Q "SELECT @@SERVERNAME"
```

ผลควรแสดง SQL Server instance เช่น:

``` text
JP-PMS-2\SQLEXPRESS
```

ถ้าพบ:

``` text
Login failed for user 'sa'
```

ให้ตรวจ:

-   Mixed Mode เปิดแล้วหรือไม่
-   `sa` ถูก Enable หรือไม่
-   Password ถูกต้องหรือไม่
-   Restart SQL Server หลังเปลี่ยน Authentication Mode แล้วหรือไม่

------------------------------------------------------------------------

## 12. ทดสอบผ่าน SSMS จากเครื่องอื่น

Connection:

``` text
Server Name:
192.168.20.3,1433

Authentication:
SQL Server Authentication

Login:
sa

Password:
<รหัสผ่าน>

Encrypt:
Mandatory

Trust Server Certificate:
✓
```

ไม่จำเป็นต้องใช้:

``` text
192.168.20.3\SQLEXPRESS
```

เมื่อกำหนด static TCP port `1433` แล้ว การใช้:

``` text
192.168.20.3,1433
```

เหมาะกับ script และ Scheduled Task มากกว่า เพราะไม่ต้องพึ่ง SQL Server Browser
เพื่อ resolve named instance

------------------------------------------------------------------------

## 13. Configuration สำหรับ Database Clone

ตัวอย่าง `.env`:

``` env
# Local source database
MSSQL_SOURCE_SERVER=localhost
MSSQL_SOURCE_DATABASE=ajinomoto_jp_ipms
MSSQL_SOURCE_USE_WINDOWS_AUTHENTICATION=true

# Remote destination database
MSSQL_DESTINATION_SERVER=192.168.20.3,1433
MSSQL_DESTINATION_DATABASE=ajinomoto_jp_ipms
MSSQL_DESTINATION_USER=sa
MSSQL_DESTINATION_PASSWORD=<PASSWORD>

# Local BACPAC / tools
MSSQL_BACPAC_DIRECTORY=C:\backup\mssql
MSSQL_SQLCMD_PATH=sqlcmd.exe
MSSQL_SQLPACKAGE_PATH=C:\Users\Administrator\.dotnet\tools\sqlpackage.exe
```

เพิ่ม `.env` ใน `.gitignore`:

``` gitignore
.env
*.bacpac
```

------------------------------------------------------------------------

## 14. Checklist

ก่อนใช้งาน Database Clone ให้ครบทุกข้อ:

-   [ ] Server มี Static IP
-   [ ] SQL Server / SQLEXPRESS ติดตั้งแล้ว
-   [ ] SQL Server service Running
-   [ ] SSMS เชื่อม Local ด้วย Windows Authentication ได้
-   [ ] Trust Server Certificate ตั้งถูกต้อง
-   [ ] Mixed Mode เปิดแล้ว
-   [ ] `sa` Enabled
-   [ ] ตั้ง password ของ `sa`
-   [ ] TCP/IP Enabled
-   [ ] TCP Dynamic Ports ว่าง
-   [ ] TCP Port = 1433
-   [ ] Restart SQL Server แล้ว
-   [ ] `netstat` แสดง `1433 LISTENING`
-   [ ] Firewall Allow TCP 1433
-   [ ] Client `Test-NetConnection ... -Port 1433` = True
-   [ ] Client `sqlcmd` login ด้วย `sa` ได้
-   [ ] `.env` ใช้ `192.168.20.3,1433`
-   [ ] `.env` ถูก ignore จาก Git

------------------------------------------------------------------------

## Troubleshooting Flow

``` text
Client ping Server ไม่ได้
        |
        +--> ตรวจ IP / Subnet / NIC / Switch / VLAN / Firewall ICMP

Ping ได้
        |
        v
Test-NetConnection :1433
        |
        +--> False
        |     |
        |     +--> ตรวจ TCP/IP
        |     +--> ตรวจ IPAll TCP Port
        |     +--> Restart SQL Server
        |     +--> ตรวจ LISTENING
        |     +--> ตรวจ Firewall
        |
        v
      True
        |
        v
sqlcmd Login
        |
        +--> Login failed for 'sa'
        |     |
        |     +--> Mixed Mode
        |     +--> Enable sa
        |     +--> Password
        |     +--> Restart SQL Server
        |
        v
SQL Connection OK
        |
        v
Run clone-db.ps1
```
