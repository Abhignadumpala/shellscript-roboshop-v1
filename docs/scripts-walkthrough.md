# Scripts Walkthrough: How Each Script Works

> **In short:** Same RoboShop project, now **automated with shell scripts** instead of typing every command by hand. `roboshop.sh` runs on my **laptop** and creates the EC2 servers + Route 53 records through the AWS CLI. Each component script (`01-mongodb.sh`…) runs **on its own server** and installs that service. GitHub carries the scripts from my laptop to the servers.

**Progress**

| # | Script | Server | Status |
|---|--------|--------|--------|
| 01 | `01-mongodb.sh` | roboshop-mongodb | ✅ MongoDB 7.0 |
| 02 | `02-redis.sh` | roboshop-redis | ✅ Redis 7, 21 s |
| 03 | `03-mysql.sh` | roboshop-mysql | ✅ MySQL 8.4.11, 40 s (+ root@localhost bug found and fixed) |
| 04 | `04-rabbitmq.sh` | roboshop-rabbitmq | ✅ 36 s, re-run safe (SKIPPING) |
| 05 | `05-catalogue.sh` | roboshop-catalogue | ✅ 63 s, 11 products |
| 06–10 | user, cart, shipping, payment, frontend | | ⏭️ next |

## Table of Contents

1. [Big picture: what runs where](#big-picture-what-runs-where)
2. [Files in this repo](#files-in-this-repo)
3. [Security groups: one common SG + one SG per component](#security-groups-one-common-sg--one-sg-per-component)
4. [roboshop.sh: create servers + DNS](#roboshopsh-create-servers--dns)
5. [01-mongodb.sh: install MongoDB on the server](#01-mongodbsh-install-mongodb-on-the-server)
6. [How I ran it (step by step)](#how-i-ran-it-step-by-step)
7. [Result](#result)
8. [Better logging: timestamp, log levels, $SECONDS](#better-logging-timestamp-log-levels-seconds)
9. [02-redis.sh](#02-redissh)
10. [03-mysql.sh (and the root@localhost bug)](#03-mysqlsh-and-the-rootlocalhost-bug)
11. [04-rabbitmq.sh + idempotency](#04-rabbitmqsh--idempotency)
12. [05-catalogue.sh: first app service](#05-cataloguesh-first-app-service)
13. [sed quick recap](#sed-quick-recap)
14. [Shell scripts vs real-time tools](#shell-scripts-vs-real-time-tools)
15. [Key takeaways](#key-takeaways)
16. [Interview Questions](#interview-questions)

[← Back to project README](../README.md) · [Problems I hit and fixes](troubleshooting.md) · [Debugging guide](debugging-guide.md) · [Interview questions](interview-questions.md)

---

## Big picture: what runs where

```
 MY UBUNTU LAPTOP                              AWS
 ┌───────────────────────────┐          ┌──────────────────────────────┐
 │ shellscript-roboshop-v1/  │          │ roboshop-mongodb (RHEL 9)    │
 │                           │          │                              │
 │  ├ roboshop.sh ──① runs here──────────▶ creates this VM + DNS      │
 │  ├ 01-mongodb.sh          │          │ /root/shellscript-roboshop-v1│
 │  └ mongo.repo             │          │  └ 01-mongodb.sh ──④ runs here│
 └────────────┬──────────────┘          └──────────────▲───────────────┘
              │ ② git push                             │ ③ ssh + git clone
              ▼                                        │
        ┌──────────────────────────────────────────────┐
        │ GitHub: Abhignadumpala/shellscript-roboshop-v1 │
        └──────────────────────────────────────────────┘
```

| Step | Where | What | Why |
|------|-------|------|-----|
| ① | Laptop | `bash roboshop.sh mongodb` | Calls the **AWS API**: creates the VM and DNS record. Installs nothing inside the VM |
| ② | Laptop → GitHub | `git push` | The new VM is empty; GitHub delivers the scripts |
| ③ | MongoDB VM | `ssh` → `sudo su -` → `git clone` | Same files now exist **inside** the server |
| ④ | MongoDB VM | `bash 01-mongodb.sh` | `dnf`, `systemctl`, `sed` act on **the machine they run on** |

> `01-mongodb.sh` can't run on the laptop: it would try to install MongoDB on the laptop (and Ubuntu has no `dnf`).

## Files in this repo

| File | Runs on | Does |
|------|---------|------|
| [roboshop.sh](../roboshop.sh) | Laptop (needs AWS CLI) | Creates EC2 instances + updates Route 53 |
| [01-mongodb.sh](../01-mongodb.sh) | MongoDB server (as root) | Installs and configures MongoDB 7.0 |
| [mongo.repo](../mongo.repo) | Copied by `01-mongodb.sh` and `05-catalogue.sh` | Tells `dnf` where to download MongoDB 7.0 (server, and the `mongosh` client) |
| [02-redis.sh](../02-redis.sh) | Redis server | Installs Redis 7, opens it to other servers |
| [03-mysql.sh](../03-mysql.sh) | MySQL server | Installs MySQL 8.4, sets the root password, checks the login |
| [04-rabbitmq.sh](../04-rabbitmq.sh) | RabbitMQ server | Installs RabbitMQ, creates the `roboshop` app user (skips if it exists) |
| [rabbitmq.repo](../rabbitmq.repo) | Copied by `04-rabbitmq.sh` | Erlang + RabbitMQ repos (not in RHEL) |
| [05-catalogue.sh](../05-catalogue.sh) | Catalogue server | Node.js 24 app: user, code, npm, systemd service, product data |
| [catalogue.service](../catalogue.service) | Copied by `05-catalogue.sh` | systemd unit with a `DOMAIN_NAME` placeholder |

## Security groups: one common SG + one SG per component

Every instance gets **two** SGs:

```
roboshop-mongodb  →  roboshop-mongodb + roboshop-common
roboshop-redis    →  roboshop-redis   + roboshop-common
```

| SG | Inbound rules |
|----|---------------|
| **roboshop-common** | Only **SSH 22 from My IP**. Attached to every instance |
| roboshop-frontend | 80 from anywhere |
| roboshop-mongodb | 27017 from catalogue, user |
| roboshop-redis | 6379 from user, cart |
| roboshop-mysql | 3306 from shipping |
| roboshop-rabbitmq | 5672 from payment, dispatch · 15672 from My IP |
| roboshop-catalogue | 8080 from frontend, cart |
| roboshop-user | 8080 from frontend, payment |
| roboshop-cart | 8080 from frontend, shipping, payment |
| roboshop-shipping / payment | 8080 from frontend |
| roboshop-dispatch | none (only connects out to RabbitMQ) |

> **Why a common SG:** SSH is in **one** place. If my home IP changes, I update **one** rule, not 11 SGs.

## roboshop.sh: create servers + DNS

```bash
bash roboshop.sh mongodb redis mysql      # one server per name
```

**Inputs at the top:**

| Variable | Value |
|----------|-------|
| `ami_id` | `ami-0055977a6e828a4f4` (Redhat-9-DevOps-Practice) |
| `instance_type` | `t3.micro` |
| `hosted_zone_id` | Route 53 zone of my domain |
| `domain_name` | `abhignadevops.store` |
| Key pair | None (password login for `ec2-user`) |

**What it does for each name:**

| Step | Command | Note |
|------|---------|------|
| 1. Create | `aws ec2 run-instances ... --security-groups "roboshop-common" "roboshop-$instance"` | SG **names** work in the default VPC |
| 2. Wait | `aws ec2 wait instance-running` | Public IP may be empty right after launch |
| 3. Get IP | `if [ $instance != "frontend" ]` → private IP, `else` → public IP | |
| 4. DNS | `aws route53 change-resource-record-sets` with `UPSERT` | Creates the record, or overwrites the old IP |

| Server | IP used | Route 53 record |
|--------|---------|-----------------|
| mongodb, redis, cart… | **Private** IP | `mongodb.abhignadevops.store` |
| frontend | **Public** IP | `abhignadevops.store` |

> **UPSERT** = **UP**date if it exists, in**SERT** if it doesn't.

**Quotes in the Route 53 JSON:** variables don't work inside single quotes. Close the quote around each variable:
```bash
'"Name": "'$r53_record_name'",'
```
→ `"Name": "mongodb.abhignadevops.store",`

## 01-mongodb.sh: install MongoDB on the server

**Common part** (same in every component script):

| Code | Meaning |
|------|---------|
| `user_id=$(id -u)` | root = `0` |
| `if [ $user_id -ne 0 ]; then ... exit 1` | Stop unless run as root (`dnf` and `systemctl` need root) |
| `logs_file="${logs_folder}/${0}.log"` | `$0` = script name → `/var/log/roboshop/01-mongodb.sh.log` |
| `mkdir -p $logs_folder` | Create the log folder; no error if it exists |
| `$(date +"%F %T")` | Date and time, e.g. `2026-10-22 00:15:30` |
| `&>> $logs_file` | Output **and** errors appended to the log |
| `R`, `G`, `Y`, `N` | Colors: red, green, yellow, normal |

**validate function** = checks each step:

```bash
validate(){
    if [ $1 -ne 0 ]; then
        echo -e "${2}..${R}FAILED${N}" | tee -a $logs_file
        exit 1
    else
        echo -e "${2}..${G}SUCCESS${N}" | tee -a $logs_file
    fi
}

dnf install mongodb-org -y &>> $logs_file
validate $? "Install MongoDB"
```

| Piece | Meaning |
|-------|---------|
| `$?` → `$1` | Exit code of the last command (`0` = success) |
| `"Install MongoDB"` → `$2` | Message to print |
| `echo -e` | Makes the color codes work |
| `tee -a` | Show on screen **and** append to the log |
| `exit 1` | Stop at the first failure |

**MongoDB steps:**

| Step | Command | Why |
|------|---------|-----|
| 1 | `cp mongo.repo /etc/yum.repos.d/mongo.repo` | Repo for MongoDB 7.0 (8.0 crashes on this AMI). Run from inside the folder |
| 2 | `dnf install mongodb-org -y` | Install |
| 3 | `systemctl enable mongod` + `start` | Start on boot + start now |
| 4 | `sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf` | Listen on all addresses so catalogue and user can connect |
| 5 | `systemctl restart mongod` | Config is read only at start |

```
Am I root? ─no─▶ "run with sudo" → exit 1
   │yes
   ▼
log folder → start time
repo → install → enable+start → sed → restart
   each step: validate → ✅ SUCCESS / ❌ FAILED + stop
```

## How I ran it (step by step)

**On the laptop:**
```bash
cd ~/shellscript-roboshop-v1
bash roboshop.sh mongodb
git push
```

**On the MongoDB server:**
```bash
ssh ec2-user@<public-ip>
sudo su -
dnf install git -y
git clone https://github.com/Abhignadumpala/shellscript-roboshop-v1.git
cd shellscript-roboshop-v1
bash 01-mongodb.sh
```

> Changed a script later? Push from the laptop, then `git pull` on the server.

## Result

**roboshop.sh mongodb**
```
Creating instance: mongodb
mongodb ID: i-0b336bf4b51e709ea
mongodb IP: 172.31.0.236
DNS updated: mongodb.abhignadevops.store -> 172.31.0.236
```

**01-mongodb.sh**
```
Adding mongo repo..SUCCESS
Install MongoDB..SUCCESS
Enable and start MongoDB..SUCCESS
Updating remote connections to MongoDB..SUCCESS
Restarting MongoDB..SUCCESS
```

| Check | Result |
|-------|--------|
| Instance | `t3.micro`, RHEL 9 practice AMI, SGs `roboshop-mongodb` + `roboshop-common` |
| Route 53 | `mongodb.abhignadevops.store` → `172.31.0.236`, change status `INSYNC` |
| MongoDB | Installed, enabled, listening on `0.0.0.0:27017` |

**Stop vs start:** after a stop/start, the **private IP stays the same** (DNS still works) but the **public IP changes**.

## Better logging: timestamp, log levels, $SECONDS

From `02-redis.sh` on, every script uses an improved common part:

```bash
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
...
echo "$(timestamp) [INFO] script completed in $SECONDS seconds" | tee -a $logs_file
```

| Piece | Meaning |
|-------|---------|
| `timestamp()` | A function: every line gets the date and time, like real logs |
| `[INFO]` / `[ERROR]` | **Log level**: easy to search with `grep ERROR` |
| `$SECONDS` | **Built-in** bash variable: seconds since the script started. Must be CAPITALS (`$seconds` is empty) |
| `&>> $logs_file` on `dnf` | Hundreds of dnf lines go to the log, the screen shows only SUCCESS lines |

```
2026-10-22 20:33:29 [INFO] ==== Script started execution ======
2026-10-22 20:33:49 [INFO] installing redis..SUCCESS
2026-10-22 20:33:50 [INFO] script completed in 21 seconds
```

**One validate for a group of commands**

```bash
dnf module disable redis -y &>> $logs_file
dnf module enable redis:7 -y &>> $logs_file
dnf install redis -y &>> $logs_file
validate $? "installing redis"
```

| Style | Pro | Con |
|-------|-----|-----|
| One validate **per command** | Catches every failure | Longer script |
| One validate **per group** (class) | Shorter | `$?` = only the **last** command; an earlier failure (e.g. `enable redis:7`) is missed |

> Script looks frozen? Its output goes to the log. Open a 2nd SSH session: `tail -f /var/log/roboshop/<script>.log`.

## 02-redis.sh

| Step | Command |
|------|---------|
| 1 | `dnf module disable redis -y` → `dnf module enable redis:7 -y` → `dnf install redis -y` |
| 2 | `sed -i -e 's/^bind 127.0.0.1/bind 0.0.0.0/' -e 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf` |
| 3 | `systemctl enable redis` + `systemctl start redis` |

| vs MongoDB | MongoDB | Redis |
|------------|---------|-------|
| Repo file | ✅ `mongo.repo` | ❌ already in RHEL repos |
| Version | From the repo | `dnf module` disable → enable `:7` |
| Config | `bind` only | `bind` **and** `protected-mode` (two locks) |
| Restart needed? | Yes (sed after start) | No: **sed before the first start** |

![02-redis.sh run](images/handson/02-redis-run.png)

## 03-mysql.sh (and the root@localhost bug)

```bash
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
```

![03-mysql.sh run](images/handson/03-mysql-run.png)

**The bug:** the script said SUCCESS, but `mysql -uroot -pRoboShop@1` gave `ERROR 1045 Access denied for user 'root'@'localhost'`.

**Proof** (logged in with no password, which only works if the password is empty):
```
mysql -uroot -e "SELECT user, host, plugin, authentication_string='' AS no_password FROM mysql.user;"
| root | %         | caching_sha2_password | 0 |   ← has the password
| root | localhost | caching_sha2_password | 1 |   ← EMPTY password
```

In MySQL a user = **name + where it logs in from**. `root` is really **2 accounts**:

| Account | Who logs in | After `--set-root-pass` |
|---------|-------------|-------------------------|
| `root@'%'` | Other servers (shipping, `mysql -h <host>`) | ✅ RoboShop@1 |
| `root@localhost` | The MySQL server itself | ❌ empty |

```
                MySQL server
   ┌───────────────────────────────┐
   │ mysql -uroot (on this server) │ ← root@localhost   no password ❌
   └───────────────────────────────┘
                 ▲ network :3306
 shipping server ┘                   ← root@'%'         RoboShop@1 ✅
```

| Question | Answer |
|----------|--------|
| Did I miss a step? | No. The trainer's doc has only `mysql_secure_installation --set-root-pass` |
| Why no error for the trainer? | The doc verifies with plain `mysql` (**no password**), which only works **because** root@localhost is empty. Shipping connects with `-h` as `root@'%'`, so the app works |
| Does the app need the fix? | No. It's a **security** fix: anyone on the server had passwordless MySQL root |
| Fix | `ALTER USER 'root'@'localhost' IDENTIFIED BY 'RoboShop@1';` + a **login check** step |

> **Lesson:** a command can return success without doing everything. Validate the **result** (log in), not only the exit code.
> Real time: apps use their own least-privilege user (`shipping` → only the `cities` DB), and passwords come from **Secrets Manager / SSM**, not from code in GitHub.

## 04-rabbitmq.sh + idempotency

| Step | Command |
|------|---------|
| 1 | `cp rabbitmq.repo /etc/yum.repos.d/rabbitmq.repo` |
| 2 | `dnf install erlang rabbitmq-server -y` |
| 3 | `systemctl enable rabbitmq-server` + `start` |
| 4 | `rabbitmqctl add_user roboshop roboshop123` (only if missing) |
| 5 | `rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"` = configure, write, read on vhost `/` |

![04-rabbitmq.sh run and checks](images/handson/04-rabbitmq-run-verify.png)

| Check | Meaning |
|-------|---------|
| `*:5672` | AMQP port, used by payment and dispatch |
| `0.0.0.0:25672` | RabbitMQ's clustering port (not used here) |
| `guest [administrator]` | Default user, can only log in from the same server |
| `roboshop []` | App user, no admin tag needed |

**Idempotent** = safe to run again. On a 2nd run `add_user roboshop` fails ("user already exists") → validate → script stops. Fix: **check first**.

```bash
rabbitmqctl list_users | grep -qw "roboshop"
if [ $? -ne 0 ]; then
    rabbitmqctl add_user roboshop roboshop123 &>> $logs_file
    validate $? "Creating RabbitMQ user for Roboshop"
else
    echo -e "$(timestamp) [INFO] RabbitMQ user already exist...${Y}SKIPPING${N}" | tee -a $logs_file
fi
```

| Part | Meaning |
|------|---------|
| `grep -q` | Quiet: print nothing, only set `$?` (0 = found) |
| `grep -w` | Whole word: `roboshop` but not `roboshop2` |
| `set_permissions` outside the `if` | Safe to run every time |

**2nd run (tested):** user step → yellow **SKIPPING**, everything else SUCCESS.

![04-rabbitmq.sh 2nd run: SKIPPING](images/handson/04-rabbitmq-rerun-skipping.png)

> The 2nd run took 86 s (82 s in `dnf install`): dnf refreshes the 4 RabbitMQ repos' metadata (`metadata_expire=300`) and checks signatures before saying "already installed".

## 05-catalogue.sh: first app service

![roboshop.sh catalogue](images/handson/05-roboshop-sh-catalogue.png)

| # | Step | Command |
|---|------|---------|
| 1 | Node.js 24 | `dnf module disable nodejs` → `enable nodejs:24` → `install nodejs` |
| 2 | App user (if missing) | `id roboshop` → `useradd --system --home /app --shell /sbin/nologin ... roboshop` |
| 3 | App folder | `mkdir -p /app` |
| 4 | Download | `curl -L -o /tmp/catalogue.zip <artifact URL>` |
| 5 | Unzip | `cd /app` → `rm -rf /app/*` → `unzip /tmp/catalogue.zip` |
| 6 | Libraries | `npm install` |
| 7 | Service | `cp $script_dir/catalogue.service /etc/systemd/system/` → `sed` the domain |
| 8 | Start | `systemctl daemon-reload` → `enable` → `start catalogue` |
| 9 | Mongo client | `cp $script_dir/mongo.repo ...` → `dnf install mongodb-mongosh -y` |
| 10 | Products | `mongosh --host mongodb.$domain_name </app/db/master-data.js` |

**New tricks in this script**

| Trick | Code | Why |
|-------|------|-----|
| Remember the script folder | `script_dir=$PWD` (at the top) | After `cd /app`, `cp catalogue.service` looks in `/app` → "No such file" |
| Clean before unzip | `rm -rf /app/*` | On a re-run unzip asks "replace?"; output goes to the log, so the script **looks frozen** |
| Skip existing user | `id roboshop` + `if` | `useradd` fails on a 2nd run |
| Placeholder in the service file | `mongodb.DOMAIN_NAME` + `sed -i "s/DOMAIN_NAME/$domain_name/"` | Domain lives in **one** variable; DNS name, not IP |
| `sed` the **copy**, not the repo file | `cp` first, then `sed` on `/etc/systemd/system/catalogue.service` | The repo file keeps `DOMAIN_NAME`, git stays clean, works again next run |
| `daemon-reload` | before `start` | systemd reads the new unit file |

**catalogue.service**

![catalogue.service](images/handson/05-catalogue-service.png)

```
repo file:    mongodb://mongodb.DOMAIN_NAME:27017/catalogue
   │ cp → /etc/systemd/system/   then   sed s/DOMAIN_NAME/abhignadevops.store/
   ▼
on server:    mongodb://mongodb.abhignadevops.store:27017/catalogue
```

**Result:** 63 s, then `/health` → `{"app":"OK","mongo":true}` and `/products` → all **11 products**.

![05-catalogue.sh run, health and products](images/handson/05-catalogue-run-health-products.png)

> ⚠️ Not idempotent yet: the products load **only once**. A 2nd run adds them twice. Next: check `countDocuments()` before loading.

## sed quick recap

**sed = Stream EDitor**: edits text line by line without opening the file.

| Option | Meaning |
|--------|---------|
| `sed -e '...' file` | Print the result only; file not changed |
| `sed -i '...' file` | **In-place**: save the change into the file |
| `s/old/new/g` | Substitute; `g` = all matches on the line |
| `sed -i '1a text' file` | Append a line **after** line 1 |
| `sed -i '1i text' file` | Insert a line **before** line 1 |
| `sed -i '1c text' file` | Change line 1 |
| `sed -i '/^mail/c text' file` | Change the line that **starts with** `mail` |
| `sed -i -e 's/a/b/' -e 's/c/d/' file` | Two replacements in one command (Redis) |
| `sed -i "s/DOMAIN_NAME/$domain_name/" file` | **Double quotes** so `$domain_name` is replaced. Needs **3 slashes** `s/old/new/` |

## Shell scripts vs real-time tools

| Task | Today (shell) | Real-time tool |
|------|---------------|----------------|
| Create servers, SGs, DNS | `roboshop.sh` | **Terraform** |
| Install and configure software | `01-mongodb.sh` | **Ansible** |
| Package the app | Install on each server | **Docker** |
| Run many services | 11 EC2 servers | **Kubernetes** |
| Databases | Install MongoDB / MySQL / Redis | **RDS, DocumentDB, ElastiCache** |

> Shell is still used daily for small automation, CI/CD steps, EC2 user data and troubleshooting. Those tools automate these same steps.

## Key takeaways

- **Laptop** creates servers (AWS API); **each server** installs its own software.
- **GitHub** moves scripts from the laptop to the servers.
- **roboshop-common** holds SSH for all servers; component SGs hold only app ports.
- **frontend → public IP + root domain**, everything else → **private IP + `<name>.domain`**.
- **validate + `$?`** = stop at the first failed step with a clear SUCCESS / FAILED message.
- **Logs** go to `/var/log/roboshop/<script>.log`, with timestamps and `[INFO]`/`[ERROR]` levels.
- **Idempotent** scripts check before creating (`id roboshop`, `list_users | grep -qw`, `rm -rf /app/*`), so a re-run SKIPS instead of failing.
- **Validate the result, not only the exit code:** `mysql_secure_installation` said SUCCESS but left `root@localhost` without a password; a login check caught it.
- **`script_dir=$PWD`** before any `cd`, so the script still finds its own files.
- **Placeholders + sed** keep the domain in one variable; config files use **DNS names**, not IPs.

## Interview Questions

Practice questions with short answers → [interview-questions.md](interview-questions.md)

Something broken? → [Debugging guide: which error → what to check](debugging-guide.md) · [Problems I hit](troubleshooting.md)
