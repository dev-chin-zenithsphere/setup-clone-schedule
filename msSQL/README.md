# SQL Server Database Clone

โฟลเดอร์นี้ใช้ clone ฐานข้อมูล SQL Server จากเครื่องต้นทางไปยังเครื่องปลายทาง โดย export เป็น `.bacpac` ในเครื่องที่รันสคริปต์ แล้ว import ไปยังปลายทางผ่าน SQL connection โดยตรง จึงไม่ต้องใช้ shared folder, SMB หรือ Remote Desktop ที่เครื่องปลายทาง

> คำเตือน: ทุกครั้งที่รัน สคริปต์จะลบฐานข้อมูลปลายทางเดิมและสร้างใหม่ ห้ามกำหนดฐานปลายทางเป็น Production database

ก่อนเริ่มใช้งาน ให้เตรียม SQL Server ปลายทางตาม [คู่มือการตั้งค่า MSSQL Server](README-MSSQL-Server-Setup.md) โดยเฉพาะ Mixed Mode Authentication, `sa`, TCP/IP และ Firewall port `1433`.

## สิ่งที่ถูก clone

- ตาราง, schema, data, index, constraint, view, stored procedure และ function
- ไม่รวม SQL logins, SQL Server Agent jobs, linked servers และสิทธิ์ระดับ server

## สิ่งที่ต้องติดตั้ง

1. Windows PowerShell 5.1 หรือใหม่กว่า
2. `sqlcmd` (SQL Server command-line tools)
3. .NET SDK 8 หรือใหม่กว่า
4. Microsoft `SqlPackage`

ติดตั้ง `SqlPackage` ด้วย PowerShell:

```powershell
dotnet tool install -g microsoft.sqlpackage --allow-roll-forward
```

ตรวจสอบการติดตั้ง:

```powershell
& "$env:USERPROFILE\.dotnet\tools\sqlpackage.exe" /Version
sqlcmd -?
```

บัญชีต้นทางต้องอ่านฐานข้อมูลได้ และบัญชีปลายทางต้องสามารถสร้าง/ลบฐานข้อมูลได้ (`sysadmin` เป็นตัวเลือกที่ง่ายที่สุด)

## ตั้งค่า

1. คัดลอก `.env.example` เป็น `.env` หากยังไม่มีไฟล์ `.env`

```powershell
Copy-Item .env.example .env
```

2. แก้ไข `.env` ให้ตรงกับ environment ของคุณ

```dotenv
MSSQL_SOURCE_SERVER=192.168.1.10
MSSQL_SOURCE_DATABASE=StudentDB
MSSQL_SOURCE_USE_WINDOWS_AUTHENTICATION=false
MSSQL_SOURCE_USER=<SET_SOURCE_USER>
MSSQL_SOURCE_PASSWORD=<SET_SOURCE_PASSWORD>

MSSQL_DESTINATION_SERVER=100.116.118.114
MSSQL_DESTINATION_DATABASE=Students
MSSQL_DESTINATION_USER=sa
MSSQL_DESTINATION_PASSWORD=<SET_DESTINATION_PASSWORD>
MSSQL_BACPAC_DIRECTORY=C:\backup\mssql
```

`.env` และไฟล์ `.bacpac` ถูก ignore จาก Git เพื่อไม่ให้ credentials หรือข้อมูลสำรองถูก commit

## รันด้วยตนเอง

เปิด PowerShell ในโฟลเดอร์ `msSQL` แล้วรัน:

```powershell
.\clone-db.ps1
```

สคริปต์จะแสดง 5 ขั้นตอน: ตรวจต้นทาง, export BACPAC, ตรวจปลายทาง, ลบ/import ฐานปลายทาง และตรวจสอบผลลัพธ์

สคริปต์ใช้ `VerifyExtraction=False` ขณะ export เพื่อรองรับ view หรือ computed column ที่อ้าง object แบบ fully-qualified หาก import ไม่ผ่าน ให้แก้ schema reference นั้นในฐานต้นทางก่อนเปิดใช้งานตาม schedule

## ตั้งเวลารันอัตโนมัติ

สร้างหรืออัปเดต Windows Scheduled Task ให้รันทุกวันเวลา **01:00 AM**:

```powershell
.\setup-clone-schedule.ps1
```

ตรวจสอบสถานะ task:

```powershell
Get-ScheduledTaskInfo -TaskName "SQL Server Database Auto Clone"
```

สั่งรัน task ทันทีเพื่อทดสอบ:

```powershell
Start-ScheduledTask -TaskName "SQL Server Database Auto Clone"
```

Scheduled Task ต้องรันด้วย Windows account ที่เข้าถึงโฟลเดอร์โปรเจกต์, `.env`, `sqlcmd` และ `SqlPackage` ได้

## ไฟล์สำคัญ

- `clone-db.ps1` — clone database จาก `.env`
- `setup-clone-schedule.ps1` — สร้าง/อัปเดต task รายวัน 01:00 AM
- `.env` — การตั้งค่าเฉพาะเครื่องและรหัสผ่าน (ไม่ commit)
- `.env.example` — template สำหรับสร้าง `.env`
