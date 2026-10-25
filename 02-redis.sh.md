# 02-redis.sh: Redis Server

[← Project README](README.md) · [Common part of every script](00-common-part.md) · [Scripts walkthrough](docs/scripts-walkthrough.md)

## What this server does

**Redis** is an in-memory store. RoboShop uses it for **carts** (cart) and the **guest id counter** (user).

| Fact | Value |
|------|-------|
| Server | `roboshop-redis` (RHEL 9, t3.micro) |
| Software | Redis 7 (RHEL AppStream module) |
| Port | 6379 |
| Called by | user, cart |
| SG inbound | 6379 from `roboshop-user`, `roboshop-cart` |
| Config file I change | `/etc/redis/redis.conf` → `bind 0.0.0.0` **and** `protected-mode no` |
| Files used | `02-redis.sh` |
| Run time | **21 s** |

---

## Steps the script does

1. Check I'm root, start the log
2. Switch the Redis module to version 7 and install
3. Open Redis to other servers: `bind` + `protected-mode`
4. Enable + start Redis
5. Print the run time

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

**What it does:** settings, root check, log folder, and the `timestamp` + `validate` helpers. Same in every script; explained line by line in the [server notes index](00-common-part.md#the-common-part-top-of-every-script).

### 5. Start message

```bash
echo "$(timestamp) [INFO] ==== Script started execution ======" | tee -a $logs_file
```

**What it does:** prints the start time on screen and in the log.

### 6. Install Redis 7

```bash
dnf module disable redis -y &>> $logs_file
dnf module enable redis:7 -y &>> $logs_file
dnf install redis -y &>> $logs_file
validate $? "installing redis"
```

**What it does:** turns off RHEL's default Redis version, picks version 7, installs it.
**Note:** one `validate` checks only the **last** command (`$?`).

### 7. Open Redis to other servers (2 locks)

```bash
sed -i -e 's/^bind 127.0.0.1/bind 0.0.0.0/' -e 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &>> $logs_file
validate $? "Allowing remote connections to redis"
```

**What it does:** 2 changes in `/etc/redis/redis.conf` with one `sed` (`-e` per change):

| Before | After | Meaning |
|--------|-------|---------|
| `bind 127.0.0.1` | `bind 0.0.0.0` | listen for other servers, not only itself |
| `protected-mode yes` | `protected-mode no` | accept clients without a password (the SG protects it) |

**Why both:** with only `bind` changed, Redis still refuses other servers. That was my `"redis":false` bug in the manual build.

### 8. Start Redis

```bash
systemctl enable redis &>> $logs_file
systemctl start redis &>> $logs_file
validate $? "enable and start redis"
```

**What it does:** start on boot + start now.
**Why no restart:** the `sed` ran **before** the first start, so Redis reads the right config the first time.

### 9. Finish

```bash
echo "$(timestamp) [INFO] script completed in  $SECONDS seconds" | tee -a $logs_file
```

**What it does:** prints the run time (21 s on my run).

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

dnf module disable redis -y &>> $logs_file
dnf module enable redis:7 -y &>> $logs_file
dnf install redis -y &>> $logs_file
validate $? "installing redis"

sed -i -e 's/^bind 127.0.0.1/bind 0.0.0.0/' -e 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf &>> $logs_file
validate $? "Allowing remote connections to redis"

systemctl enable redis &>> $logs_file
systemctl start redis &>> $logs_file
validate $? "enable and start redis"

echo "$(timestamp) [INFO] script completed in  $SECONDS seconds" | tee -a $logs_file
echo "$(timestamp) [INFO] ==== Script completed execution ======" | tee -a $logs_file
```

</details>

---

## Run + result

![02-redis.sh run](docs/images/handson/02-redis-run.png)

## Verify

```bash
redis-cli ping                           # PONG
ss -tlnp | grep 6379                     # 0.0.0.0:6379
redis-cli config get protected-mode      # "no"  ← the live value
```

---

## Problems I hit

| Problem | Cause | Fix |
|---------|-------|-----|
| (manual build) user showed `"redis":false`, log `Socket closed unexpectedly` | I changed `bind` but not `protected-mode` | Script changes **both**, so it can't happen again |
| (manual build) `systemctl start redis` didn't apply the change | `start` does nothing on a running service | `restart` after a config change |

---

## Interview questions

**1. What is Redis protected mode?**
If no password is set, Redis refuses clients from other servers. Either set a password (`requirepass`) or turn protected mode off and protect it with the SG.

**2. Why `dnf module disable` then `enable redis:7`?**
RHEL offers several Redis versions as modules. Disabling the default and enabling `:7` installs exactly version 7.

**3. Why no restart in this script?**
The `sed` runs before the first start, so Redis reads the right config the first time.
