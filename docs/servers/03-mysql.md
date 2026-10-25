# 03-mysql.sh: MySQL Server

[← Server notes](README.md) · [Project README](../../README.md) · [Scripts walkthrough](../scripts-walkthrough.md)

## What this server does

**MySQL** stores the **cities and shipping costs**. Only shipping uses it.

| Fact | Value |
|------|-------|
| Server | `roboshop-mysql` (RHEL 9, t3.micro) |
| Software | MySQL 8.4 (RHEL AppStream module) |
| Port | 3306 |
| Called by | shipping |
| SG inbound | 3306 from `roboshop-shipping` |
| Config file I change | none (listens on all interfaces by default) |
| Files used | `03-mysql.sh` |
| Run time | **40 s** |

---

## Steps the script does

1. Check I'm root, start the log
2. Enable MySQL 8.4 and install
3. Enable + start `mysqld`
4. Set the root password
5. Fix the empty `root@localhost` password
6. **Check** that root can log in with the password

---

## The code, block by block

### 1–4. The common part

```bash
user_id=$(id -u)
logs_folder="/var/log/roboshop"
logs_file="${logs_folder}/${0}.log"
...
if [ $user_id -ne 0 ]; then ... exit 1; fi
mkdir -p $logs_folder
timestamp(){ ... }
validate(){ ... }
```

**What it does:** settings, root check, log folder, and the `timestamp` + `validate` helpers. Same in every script; explained line by line in the [server notes index](README.md#the-common-part-top-of-every-script).

### 5. Install MySQL 8.4

```bash
dnf module enable mysql:8.4 -y &>> $logs_file
dnf install mysql-server -y &>> $logs_file
validate $? "installing mysql"
```

**What it does:** picks MySQL 8.4 and installs the server.

### 6. Start MySQL

```bash
systemctl enable mysqld &>> $logs_file
systemctl start mysqld &>> $logs_file
validate $? "start and enable mysql"
```

**What it does:** start on boot + start now. The service is called **`mysqld`**.

### 7. Set the root password

```bash
mysql_secure_installation --set-root-pass <password> &>> $logs_file
validate $? "setup MySQL root user and password"
```

**What it does:** sets the root password. **But only for `root@'%'`** (logins from other servers).

### 8. Fix the empty `root@localhost`

```bash
mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '<password>';" &>> $logs_file
validate $? "setting password for root@localhost"
```

**What it does:** sets the same password on `root@localhost` (logins from the MySQL server itself).
**Why:** after block 7 it was still **empty**: anyone on the server could log in as root with no password.

| Account | Who logs in | After block 7 | After block 8 |
|---------|-------------|---------------|---------------|
| `root@'%'` | other servers | ✅ password | ✅ |
| `root@localhost` | the MySQL server itself | ❌ empty | ✅ password |

### 9. Prove the login works

```bash
mysql -uroot -p<password> -e "SELECT VERSION();" &>> $logs_file
validate $? "checking root login with password"
```

**What it does:** logs in **with** the password and asks for the version. Wrong password → FAILED.
**Why:** exit code 0 in block 7 didn't prove the password worked. This step checks the real **result**.

<details>
<summary><b>Full script in one piece</b> (click to open)</summary>

```bash
#!/bin/bash

user_id=$(id -u)
logs_folder="/var/log/roboshop"
logs_file="${logs_folder}/${0}.log"
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

if [ $user_id -ne 0 ]; then
    echo "Please run this script with sudo access.."
    exit 1
fi

mkdir -p $logs_folder

timestamp(){
    date +"%F %T"
}

validate(){
    if [ $1 -ne 0 ]; then
        echo -e "$(timestamp) [ERROR] ${2}..${R}FAILED${N}" | tee -a $logs_file
        exit 1
    else
        echo -e "$(timestamp) [INFO] ${2}..${G}SUCCESS${N}" | tee -a $logs_file
    fi
}

echo "$(timestamp) [INFO] ==== Script started execution ======" | tee -a $logs_file

dnf module enable mysql:8.4 -y &>> $logs_file
dnf install mysql-server -y &>> $logs_file
validate $? "installing mysql"

systemctl enable mysqld &>> $logs_file
systemctl start mysqld &>> $logs_file
validate $? "start and enable mysql"

mysql_secure_installation --set-root-pass RoboShop@1 &>> $logs_file
validate $? "setup MySQL root user and password"

mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'RoboShop@1';" &>> $logs_file
validate $? "setting password for root@localhost"

mysql -uroot -pRoboShop@1 -e "SELECT VERSION();" &>> $logs_file
validate $? "checking root login with password"

echo "$(timestamp) [INFO] script completed in  $SECONDS seconds" | tee -a $logs_file
echo "$(timestamp) [INFO] ==== Script completed execution ======" | tee -a $logs_file
```

</details>

---

## The bug I found: SUCCESS, but login failed

1. The script said all SUCCESS.
2. `mysql -uroot -p<password>` → `ERROR 1045 Access denied for user 'root'@'localhost'`.
3. In MySQL a user = **name + where it logs in from**. `root` is really 2 accounts:

| Account | Who logs in | After `--set-root-pass` |
|---------|-------------|-------------------------|
| `root@'%'` | Other servers (shipping) | ✅ password set |
| `root@localhost` | The MySQL server itself | ❌ **empty** |

4. Proof: `SELECT user, host, authentication_string='' FROM mysql.user;` → `root | localhost | 1` (empty).
5. Fix: `ALTER USER 'root'@'localhost' ...` + a **login check** step.

> **Lesson:** exit code 0 doesn't prove it worked. Validate the **result**.

---

## Run + result

![03-mysql.sh run](../images/handson/03-mysql-run.png)

## Verify

```bash
systemctl status mysqld                        # active (running)
ss -tlnp | grep 3306                           # *:3306
mysql -uroot -p<password> -e 'SELECT VERSION();'   # 8.4.x
```

---

## Problems I hit

| Problem | Cause | Fix |
|---------|-------|-----|
| `ERROR 1045` for `root@localhost` after SUCCESS | `--set-root-pass` only set `root@'%'` | `ALTER USER` + login check |
| Security hole | Anyone on the server had passwordless MySQL root | Same fix |

---

## Interview questions

**1. Why is `root@localhost` different from `root@'%'`?**
MySQL accounts are user + host. `localhost` = connections from the server itself; `%` = from any other host. Each has its own password.

**2. Why add a login check after setting the password?**
The command can exit 0 without doing everything. Logging in proves the password really works.

**3. In production, would the app use root?**
No. It gets its own user with access only to its database, and the password comes from Secrets Manager / SSM, not from the script.
