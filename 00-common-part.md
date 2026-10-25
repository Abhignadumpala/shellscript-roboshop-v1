# Common Part of Every Script + Index of Script Notes

[← Back to project README](README.md) · [Scripts walkthrough](docs/scripts-walkthrough.md)

Each script has its explanation **right below it** in the folder (`<script>.sh.md`). Each note explains **one script**: what the server does, the full code, every line, how I ran it, how I checked it, and the problems I hit.

| # | Note | Server | Port | Status |
|---|------|--------|------|--------|
| 0 | [roboshop.sh](roboshop.sh.md) | my laptop | – | ✅ creates EC2 + DNS |
| 1 | [01-mongodb.sh](01-mongodb.sh.md) | mongodb | 27017 | ✅ |
| 2 | [02-redis.sh](02-redis.sh.md) | redis | 6379 | ✅ 21 s |
| 3 | [03-mysql.sh](03-mysql.sh.md) | mysql | 3306 | ✅ 40 s |
| 4 | [04-rabbitmq.sh](04-rabbitmq.sh.md) | rabbitmq | 5672 | ✅ 36 s |
| 5 | [05-catalogue.sh](05-catalogue.sh.md) | catalogue | 8080 | ✅ 63 s |
| 6–11 | user, cart, shipping, payment, dispatch, frontend | | | next |

---

## The common part (top of every script)

Every component script starts with the same block. It's explained once here, and the server notes only explain what's different.

```bash
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
```

| Line | What it does | Why |
|------|--------------|-----|
| `user_id=$(id -u)` | Saves my user ID. root = `0` | `dnf` and `systemctl` need root |
| `logs_file="${logs_folder}/${0}.log"` | `$0` = script name → `/var/log/roboshop/02-redis.sh.log` | One log file per script |
| `R`, `G`, `Y`, `N` | Colour codes: red, green, yellow, normal | FAILED red, SUCCESS green, SKIPPING yellow |
| `if [ $user_id -ne 0 ]; then ... exit 1` | Stops if not root | Fail early with a clear message |
| `mkdir -p $logs_folder` | Creates the log folder | `-p` = no error if it already exists |
| `timestamp()` | Prints date + time, e.g. `2026-10-22 20:33:29` | Every log line gets a time, like real logs |
| `validate $? "step"` | `$1` = exit code of the last command, `$2` = message | `0` → SUCCESS, else FAILED + `exit 1` (stop at the first failure) |
| `echo -e` | Makes the colour codes work | Without `-e` you see `\e[31m` as text |
| `tee -a $logs_file` | Shows on screen **and** appends to the log | Screen for me, log for later |
| `&>> $logs_file` (on commands) | Sends output **and** errors to the log | Screen stays clean: only SUCCESS / FAILED lines |
| `$SECONDS` (at the end) | Built-in: seconds since the script started | Measures run time. Must be CAPITALS |

> `01-mongodb.sh` was my first script, so it has the older version: no `timestamp()` and no `[INFO]` / `[ERROR]`.

---

## How I run any script

**On my laptop:**
```bash
bash roboshop.sh <name>          # creates the server + DNS record
git push                         # scripts are on GitHub
```

**On the new server:**
```bash
ssh ec2-user@<public-ip>
sudo su -
dnf install git -y
git clone https://github.com/Abhignadumpala/shellscript-roboshop-v1.git
cd shellscript-roboshop-v1
bash 0N-<name>.sh
```

**Script looks frozen?** Open a 2nd SSH session: `tail -f /var/log/roboshop/0N-<name>.sh.log`
