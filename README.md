# Database Clone Schedule

ชุดสคริปต์สำหรับ clone ฐานข้อมูลจาก source ไปยัง destination แบบตั้งเวลาได้บน Windows โดย destination จะถูกลบและสร้างใหม่ทุกครั้ง จึงห้ามใช้ destination ที่เป็น production database

## สิ่งที่ต้องติดตั้ง

ใช้ Windows PowerShell 5.1 หรือ PowerShell 7 และติดตั้งเครื่องมือให้ตรงกับฐานข้อมูล:

- PostgreSQL: PostgreSQL client tools ที่มี `pg_dump.exe`, `pg_restore.exe`, และ `psql.exe` เวอร์ชันที่รองรับ server
- SQL Server: `sqlcmd`, .NET SDK 8 หรือใหม่กว่า, และ SqlPackage:

```powershell
dotnet tool install -g microsoft.sqlpackage --allow-roll-forward
sqlcmd -?
& "$env:USERPROFILE\.dotnet\tools\sqlpackage.exe" /Version
```

เครื่องที่รัน script ต้องเชื่อมต่อ TCP ไปยังทั้ง source และ destination ได้ และ SQL Server ต้องใช้ TLS certificate ที่เชื่อถือได้

## ตั้งค่า PostgreSQL

```powershell
Set-Location .\pgSQL
Copy-Item .env.example .env
notepad .env
.\clone-db.ps1
```

ตั้งค่า `PG_SOURCE_HOST` เป็น IP ของ source และใส่ `PG_SOURCE_USER` / `PG_SOURCE_PASSWORD` รวมถึง destination ใน `.env` ห้าม commit `.env` และควรใช้บัญชีที่มีสิทธิ์เท่าที่จำเป็น: source อ่านข้อมูลได้, destination สร้าง/ลบ database ได้

หลังทดสอบสำเร็จ ตั้ง schedule:

```powershell
.\setup-clone-schedule.ps1
Get-ScheduledTaskInfo -TaskName "AOI Database Auto Clone"
```

## ตั้งค่า SQL Server

ใช้ชุดสคริปต์ในโฟลเดอร์ `msSQL` แล้วสร้าง `.env`:

```powershell
Set-Location .\msSQL
Copy-Item .env.example .env
notepad .env
.\clone-db.ps1
```

สำหรับ source แบบ SQL Authentication ให้กำหนด `MSSQL_SOURCE_SERVER` เป็น IP, `MSSQL_SOURCE_USE_WINDOWS_AUTHENTICATION=false`, `MSSQL_SOURCE_USER` และ `MSSQL_SOURCE_PASSWORD` หากใช้ Windows Authentication ให้ตั้งค่าเป็น `true` และไม่ต้องระบุ source user/password

ตั้งเวลารันทุกวัน:

```powershell
.\setup-clone-schedule.ps1
Get-ScheduledTaskInfo -TaskName "SQL Server Database Auto Clone"
```

## ข้อควรระวัง

- ทดสอบ manual clone ก่อนตั้ง schedule ทุกครั้ง
- สำรอง destination หากข้อมูลเดิมสำคัญ เพราะ script จะลบทิ้งก่อน import
- ถ้า SQL Server ใช้ self-signed/untrusted certificate ให้ตั้ง `MSSQL_TRUST_SERVER_CERTIFICATE=true`; การตั้งค่านี้ข้ามการยืนยันตัวตนของ certificate และควรใช้เฉพาะเครือข่ายที่เชื่อถือได้
- รักษาสิทธิ์ของโฟลเดอร์โครงการและ `.env` ให้เฉพาะ account ที่รัน Scheduled Task เข้าถึงได้
