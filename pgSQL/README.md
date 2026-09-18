# PostgreSQL Automatic Database Clone

ระบบสำหรับ Clone PostgreSQL Database จากเครื่องต้นทางไปยัง PostgreSQL Server ปลายทางแบบอัตโนมัติ โดยใช้ `pg_dump`, `pg_restore`, PowerShell และ Windows Task Scheduler

## Overview

ระบบแบ่งออกเป็น 2 Script หลัก

```text
scripts/
├── clone-db.ps1
└── setup-clone-schedule.ps1
```

### `clone-db.ps1`

ทำหน้าที่ Clone Database จริง โดยมีขั้นตอนหลักดังนี้

```text
Source PostgreSQL
        │
        │ 1. Test Connection
        ▼
    pg_dump
        │
        │ 2. Create Backup
        ▼
   .backup File
        │
        │ 3. Verify Backup
        ▼
Destination PostgreSQL
        │
        │ 4. Test Connection
        │
        │ 5. Drop/Create Database
        │
        │ 6. pg_restore
        ▼
  Cloned Database
        │
        │ 7. Verify
        ▼
      Success
```

### `setup-clone-schedule.ps1`

ทำหน้าที่สร้างหรือแก้ไข Windows Task Scheduler เพื่อเรียก `clone-db.ps1` ตามเวลาที่กำหนด

```text
Windows Task Scheduler
        │
        │ Scheduled Time
        ▼
   powershell.exe
        │
        ▼
    clone-db.ps1
        │
        ▼
   Database Clone
```

---

# Requirements

เครื่องที่ใช้รัน Script ต้องมี:

- Windows
- PowerShell
- PostgreSQL Client Tools
- `pg_dump.exe`
- `pg_restore.exe`
- `psql.exe`
- Network access ไปยัง PostgreSQL Server ปลายทาง
- PostgreSQL user ที่มีสิทธิ์สร้างและลบ Database

ตัวอย่าง PostgreSQL Tools:

```text
C:\Program Files\PostgreSQL\18\bin\
```

ตรวจสอบ:

```powershell
Test-Path "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe"
Test-Path "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe"
Test-Path "C:\Program Files\PostgreSQL\18\bin\psql.exe"
```

ควรได้:

```text
True
True
True
```

---

# Current Configuration

ตัวอย่าง Configuration ปัจจุบัน:

```text
SOURCE
Host     : 127.0.0.1
Port     : 5432
Database : aoi_db
User     : postgres

            ↓ CLONE

DESTINATION
Host     : 100.116.118.114
Port     : 5432
Database : aoi_db_clone
User     : postgres
```

Destination Server เชื่อมต่อผ่าน Tailscale Network

---

# Clone Process

`clone-db.ps1` ทำงานทั้งหมด 7 ขั้นตอน

## 1. Test Source Database

Script จะทดสอบการเชื่อมต่อกับ Source ก่อน

```text
127.0.0.1:5432
        ↓
     aoi_db
```

ถ้า Source เชื่อมต่อไม่ได้ Script จะหยุดทันที และจะยังไม่แก้ไข Database ปลายทาง

---

## 2. Dump Source Database

ใช้ `pg_dump` เพื่อสร้าง PostgreSQL Custom Backup

ตัวอย่าง:

```text
C:\backup\postgres\aoi_db_2026-09-15_120000.backup
```

รูปแบบชื่อไฟล์:

```text
{database}_{yyyy-MM-dd_HHmmss}.backup
```

---

## 3. Verify Backup

ใช้:

```powershell
pg_restore --list
```

เพื่อตรวจสอบว่า Backup สามารถอ่านได้ก่อนดำเนินการกับ Database ปลายทาง

---

## 4. Test Destination Server

Script จะทดสอบการเชื่อมต่อ PostgreSQL Server ปลายทาง

ตัวอย่าง:

```text
100.116.118.114:5432
```

ถ้าเชื่อมต่อไม่ได้ Script จะหยุด และจะไม่ลบ Database ปลายทาง

---

## 5. Recreate Destination Database

ก่อน Restore ระบบจะตัด Connection ที่กำลังใช้งาน Destination Database

จากนั้นทำงานเทียบเท่า:

```sql
DROP DATABASE IF EXISTS aoi_db_clone;

CREATE DATABASE aoi_db_clone;
```

> **Warning**
>
> ข้อมูลเดิมทั้งหมดใน Destination Database จะถูกลบทุกครั้งที่ Clone

ดังนั้นห้ามกำหนด `$destDb` เป็น Production Database ที่ไม่ต้องการให้ถูกลบ

---

## 6. Restore Database

ใช้ `pg_restore` นำ Backup จาก Source เข้า Destination Database

โดย Restore ข้อมูล เช่น:

- Schema
- Tables
- Data
- Sequences
- Indexes
- Constraints
- Foreign Keys

---

## 7. Verify Destination

หลัง Restore เสร็จ Script จะเชื่อมต่อ Destination Database และตรวจสอบจำนวน Table ใน `public` schema

ตัวอย่าง:

```text
database       table_count
-------------- -----------
aoi_db_clone   17
```

เมื่อทุกขั้นตอนสำเร็จจะแสดง:

```text
==============================================
 DATABASE CLONE SUCCESS
==============================================
```

---

# Changing Database

ถ้าต้องการเปลี่ยนไป Clone Database อื่น ให้แก้ Configuration ใน `clone-db.ps1`

ตัวอย่าง ต้องการ Clone:

```text
inventory_db
      ↓
inventory_db_clone
```

แก้:

```powershell
$sourceHost     = "127.0.0.1"
$sourcePort     = "5432"
$sourceDb       = "inventory_db"
$sourceUser     = "postgres"
$sourcePassword = "SOURCE_PASSWORD"

$destHost       = "100.116.118.114"
$destPort       = "5432"
$destDb         = "inventory_db_clone"
$destUser       = "postgres"
$destPassword   = "DESTINATION_PASSWORD"
```

จากนั้นระบบจะทำ:

```text
inventory_db
      │
      ├── pg_dump
      ▼
inventory_db_yyyy-MM-dd_HHmmss.backup
      │
      ├── DROP inventory_db_clone
      ├── CREATE inventory_db_clone
      │
      └── pg_restore
      ▼
inventory_db_clone
```

---

# Recommended Generic Configuration

เพื่อให้เปลี่ยน Database ได้ง่าย แนะนำกำหนด Destination และ Backup Filename จาก `$sourceDb`

```powershell
# SOURCE

$sourceHost     = "127.0.0.1"
$sourcePort     = "5432"
$sourceDb       = "aoi_db"
$sourceUser     = "postgres"
$sourcePassword = "SOURCE_PASSWORD"

# DESTINATION

$destHost       = "100.116.118.114"
$destPort       = "5432"
$destDb         = "${sourceDb}_clone"
$destUser       = "postgres"
$destPassword   = "DESTINATION_PASSWORD"

# BACKUP

$backupDir = "C:\backup\postgres"
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

$backupFile = Join-Path `
    $backupDir `
    "${sourceDb}_$timestamp.backup"
```

เมื่อเปลี่ยน:

```powershell
$sourceDb = "inventory_db"
```

ระบบจะใช้:

```text
Source Database      : inventory_db
Destination Database : inventory_db_clone
Backup                : inventory_db_yyyy-MM-dd_HHmmss.backup
```

---

# Manual Run

สามารถ Clone Database ทันทีโดยไม่ต้องรอ Task Scheduler:

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File "C:\scripts\clone-db.ps1"
```

หรือถ้าอยู่ใน directory เดียวกับ Script:

```powershell
.\clone-db.ps1
```

---

# Automatic Schedule

ใช้:

```text
setup-clone-schedule.ps1
```

สำหรับสร้าง Windows Scheduled Task

ตัวอย่าง Trigger:

```powershell
$trigger = New-ScheduledTaskTrigger `
    -Daily `
    -At "12:00PM"
```

หมายถึง:

```text
Every Day
12:00 PM
    ↓
clone-db.ps1
    ↓
Clone Database
```

หลังแก้ Schedule ต้องรัน `setup-clone-schedule.ps1` อีกครั้งเพื่อ Update Task Scheduler

```powershell
powershell.exe `
    -NoProfile `
    -ExecutionPolicy RemoteSigned `
    -File "C:\scripts\setup-clone-schedule.ps1"
```

---

# Check Scheduled Task

ตรวจสอบสถานะ:

```powershell
Get-ScheduledTask `
    -TaskName "AOI Database Auto Clone"
```

ตรวจสอบเวลารัน:

```powershell
Get-ScheduledTaskInfo `
    -TaskName "AOI Database Auto Clone"
```

ค่าที่สำคัญ:

```text
LastRunTime
LastTaskResult
NextRunTime
NumberOfMissedRuns
```

---

# Run Scheduled Task Immediately

สามารถสั่ง Task ให้ทำงานทันทีได้โดยไม่เปลี่ยน Schedule:

```powershell
Start-ScheduledTask `
    -TaskName "AOI Database Auto Clone"
```

จากนั้นตรวจสอบ:

```powershell
Get-ScheduledTaskInfo `
    -TaskName "AOI Database Auto Clone"
```

---

# Network Test

ก่อน Clone สามารถตรวจสอบ PostgreSQL Server ปลายทางได้:

```powershell
Test-NetConnection `
    100.116.118.114 `
    -Port 5432
```

ต้องได้:

```text
TcpTestSucceeded : True
```

---

# Important Notes

1. Destination Database จะถูก `DROP` และสร้างใหม่ทุกครั้ง
2. ข้อมูลที่แก้ไขเฉพาะใน Destination จะหายหลังการ Clone รอบถัดไป
3. Source Database จะไม่ถูกลบหรือแก้ไขโดยกระบวนการ Clone
4. ควรทดสอบ Manual Clone ให้สำเร็จก่อนเปิด Automatic Schedule
5. เครื่องที่รัน Task ต้องสามารถเชื่อมต่อ Source และ Destination PostgreSQL ได้
6. ถ้าใช้ Tailscale เครื่องต้นทางและปลายทางต้องสามารถติดต่อกันได้
7. ไม่ควรเก็บ PostgreSQL Password แบบ Plain Text ใน Repository

---

# Summary

ระบบทำงานในรูปแบบ:

```text
                    Windows Task Scheduler
                              │
                              ▼
                        clone-db.ps1
                              │
                ┌─────────────┴─────────────┐
                │                           │
                ▼                           │
         Source PostgreSQL                  │
             aoi_db                         │
                │                           │
                ▼                           │
             pg_dump                        │
                │                           │
                ▼                           │
          .backup file                      │
                │                           │
                ▼                           │
          pg_restore                        │
                │                           │
                ▼                           │
       Destination PostgreSQL ◄─────────────┘
          aoi_db_clone
```

การเปลี่ยน Database หลักจึงทำได้โดยแก้ Configuration ของ `clone-db.ps1` โดยไม่จำเป็นต้องแก้กระบวนการ Dump / Restore หลัก
