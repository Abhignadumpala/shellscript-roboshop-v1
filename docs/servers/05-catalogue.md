# 05-catalogue.sh: Catalogue Server

[← Server notes](README.md) · [Project README](../../README.md) · [Scripts walkthrough](../scripts-walkthrough.md)

## What this server does

**Catalogue** is a Node.js app that serves the **product list** from MongoDB. It's the first **app** server (01–04 are databases).

| Fact | Value |
|------|-------|
| Server | `roboshop-catalogue` (RHEL 9, t3.micro) |
| Software | Node.js 24 + the catalogue app |
| Port | 8080 |
| Called by | frontend, cart |
| Calls | mongodb (`MONGO_URL`) |
| SG inbound | 8080 from `roboshop-frontend`, `roboshop-cart` |
| Config file I add | `/etc/systemd/system/catalogue.service` |
| Files used | `05-catalogue.sh`, `catalogue.service`, `mongo.repo` |
| Run time | **63 s** |

---

## Steps the script does

1. Check I'm root, save the script's folder (`script_dir`)
2. Install Node.js 24
3. Create the `roboshop` system user (skip if it exists)
4. Download and unzip the app into `/app`
5. `npm install` the libraries
6. Copy `catalogue.service`, put in the real domain, start the service
7. Install the MongoDB client
8. Load the products **only if MongoDB has none**
9. **Restart** catalogue so every change is loaded

---

## The code, block by block

Each block: the code, then **what it does** and **why**, in order from top to bottom.

### 1. Settings at the top

```bash
user_id=$(id -u)
logs_folder="/var/log/roboshop"
logs_file="${logs_folder}/${0}.log"
domain_name="abhignadevops.store"
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
```

**What it does:** saves values the rest of the script uses.

| Variable | Value | Used for |
|----------|-------|----------|
| `user_id` | my user ID (`0` = root) | the root check in block 2 |
| `logs_file` | `/var/log/roboshop/05-catalogue.sh.log` (`$0` = script name) | where all output goes |
| `domain_name` | `abhignadevops.store` | the MongoDB address in blocks 9 and 11 |
| `R` `G` `Y` `N` | red, green, yellow, normal | FAILED, SUCCESS, SKIPPING colours |

### 2. Am I root?

```bash
if [ $user_id -ne 0 ]; then
    echo "Please run this script with sudo access.."
    exit 1
fi
```

**What it does:** if I'm not root, it prints a message and **stops**.
**Why:** `dnf`, `useradd` and `systemctl` only work as root. Better to stop at line 1 than fail halfway.

### 3. Log folder + remember the script's folder

```bash
mkdir -p $logs_folder
script_dir=$(dirname "$(realpath "$0")")
```

**What it does:**
1. Creates `/var/log/roboshop` (`-p` = no error if it already exists).
2. Saves the folder this script lives in, as a full path, e.g. `/root/shellscript-roboshop-v1`.

**Why:** in block 7 the script does `cd /app`. After that, `catalogue.service` and `mongo.repo` would be searched in `/app`. With `script_dir` I always use the full path.

### 4. Helper functions

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
```

**What it does:**
- `timestamp` prints the date and time: `2026-10-23 10:15:02`.
- `validate $? "message"` checks the last command: exit code `0` → green **SUCCESS**, anything else → red **FAILED** and **stop**.
- `tee -a` shows the line on screen **and** adds it to the log.

**Why:** every step is checked; the script never continues after a failure.

### 5. Install Node.js 24

```bash
dnf module disable nodejs -y &>> $logs_file
dnf module enable nodejs:24 -y &>> $logs_file
dnf install nodejs -y &>> $logs_file
validate $? "installing nodejs:24"
```

**What it does:** turns off RHEL's default Node.js version, picks version 24, installs it.
**Why:** catalogue is a Node.js app and needs v24. `&>> $logs_file` sends all the dnf output to the log so the screen stays clean.

### 6. Create the app user (only if missing)

```bash
id roboshop &>> $logs_file
if [ $? -ne 0 ]; then
   useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>> $logs_file
   validate $? "creating system user"
else
   echo -e "$(timestamp) [INFO] system user roboshop already exist...${Y}SKIPPING${N}" | tee -a $logs_file
fi
```

**What it does:**
1. `id roboshop`: does the user exist? (`$?` = 0 yes, not 0 no)
2. No → create it. Yes → print yellow **SKIPPING**.

| `useradd` option | Meaning |
|------------------|---------|
| `--system` | a user for a program, not a person |
| `--home /app` | its home folder is the app folder |
| `--shell /sbin/nologin` | nobody can log in as it |

**Why:** the app must not run as root (safer). The check makes a 2nd run not fail (**idempotent**).

### 7. Download the app code

```bash
mkdir -p /app
validate $? "creating app directory"

curl -L -o /tmp/catalogue.zip https://raw.githubusercontent.com/daws-92s/roboshop-documentation/refs/heads/main/artifacts/catalogue-v4.zip &>> $logs_file
validate $? "Downloading catalogue"

cd /app
rm -rf /app/*
unzip /tmp/catalogue.zip &>> $logs_file
validate $? "unzipping catalogue"
```

**What it does:**
1. Creates `/app`.
2. Downloads the app zip to `/tmp/catalogue.zip` (`-L` = follow redirects, `-o` = save as).
3. Goes into `/app`, **deletes old code**, unzips the new code.

**Why `rm -rf /app/*`:** on a 2nd run, `unzip` would ask "replace server.js?" and wait forever (the question is hidden in the log).

### 8. Install the app's libraries

```bash
npm install &>> $logs_file
validate $? "installing dependencies"
```

**What it does:** reads `package.json` in `/app` and downloads every library the app needs into `node_modules/`.

### 9. Install the service file with my domain

```bash
cp $script_dir/catalogue.service /etc/systemd/system/catalogue.service
validate $? "copying catalogue service"

sed -i "s/DOMAIN_NAME/$domain_name/" /etc/systemd/system/catalogue.service
validate $? "updating domain name in catalogue service"
```

**What it does:**
1. Copies my `catalogue.service` (from the script's folder) to systemd's folder.
2. In that **copy**, replaces `DOMAIN_NAME` with `abhignadevops.store`.

```
before:  MONGO_URL="mongodb://mongodb.DOMAIN_NAME:27017/catalogue"
after:   MONGO_URL="mongodb://mongodb.abhignadevops.store:27017/catalogue"
```

**Why copy first, then `sed`:** the file in my repo keeps `DOMAIN_NAME`. Git stays clean and the next run works the same.

### 10. Start catalogue

```bash
systemctl daemon-reload &>> $logs_file
systemctl enable catalogue &>> $logs_file
systemctl start catalogue &>> $logs_file
validate $? "starting and enabling catalogue"
```

| Command | Meaning |
|---------|---------|
| `daemon-reload` | systemd reads the new `catalogue.service` file |
| `enable` | start catalogue on every boot |
| `start` | start it now |

### 11. Load the products into MongoDB (only once)

```bash
cp $script_dir/mongo.repo /etc/yum.repos.d/mongo.repo
validate $? "adding mongo repo"

dnf install mongodb-mongosh -y &>> $logs_file
validate $? "installing mongodb client"

product_count=$(mongosh --host mongodb.$domain_name --quiet --eval 'db.getSiblingDB("catalogue").products.countDocuments()' 2>> $logs_file)
validate $? "connecting to mongodb"

if [ "$product_count" -eq 0 ]; then
    mongosh --host mongodb.$domain_name </app/db/master-data.js &>> $logs_file
    validate $? "loading catalogue products"
else
    echo -e "$(timestamp) [INFO] products are already loaded...${Y}SKIPPING${N}" | tee -a $logs_file
fi
```

**What it does:**
1. Adds the MongoDB repo and installs `mongosh` (the MongoDB client).
2. Connects to the MongoDB **server** and **counts** the products in the `catalogue` database.
3. Count = `0` → runs `master-data.js`, which inserts the 11 products.
4. Count > `0` → yellow **SKIPPING**.

**Why:** the app shows products from MongoDB, so they must be loaded once. Without the count check, every run would add all 11 again (**idempotent**).

### 12. Restart catalogue

```bash
systemctl restart catalogue &>> $logs_file
validate $? "restarting catalogue"
```

**What it does:** stops and starts catalogue.
**Why:** `start` (block 10) does nothing if catalogue is already running, e.g. on a 2nd run with a changed service file. `restart` always loads the latest code and config.

### 13. Finish

```bash
echo "$(timestamp) [INFO] script completed in  $SECONDS seconds" | tee -a $logs_file
echo "$(timestamp) [INFO] ==== Script completed execution ======" | tee -a $logs_file
```

**What it does:** prints how long the script took. `$SECONDS` is a built-in bash counter (63 s on my run).

### catalogue.service, line by line

```ini
[Unit]
Description=Catalogue Service
After=network-online.target

[Service]
User=roboshop
Environment=MONGO_URL="mongodb://mongodb.DOMAIN_NAME:27017/catalogue"
ExecStart=/bin/node /app/server.js
SyslogIdentifier=catalogue
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

| Line | Meaning |
|------|---------|
| `After=network-online.target` | Start after the network is up |
| `User=roboshop` | Run as the app user, not root |
| `Environment=MONGO_URL="mongodb://mongodb.DOMAIN_NAME:27017/catalogue"` | **Outgoing address**: where MongoDB is + DB name. DNS name, not IP |
| `ExecStart=/bin/node /app/server.js` | The command that starts the app |
| `Restart=on-failure` + `RestartSec=5` | If it crashes, systemd restarts it after 5 s |
| `WantedBy=multi-user.target` | Used by `enable`: start on boot |

<details>
<summary><b>Full script in one piece</b> (click to open)</summary>

```bash
#!/bin/bash

user_id=$(id -u)
logs_folder="/var/log/roboshop"
logs_file="${logs_folder}/${0}.log"
domain_name="abhignadevops.store"
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

if [ $user_id -ne 0 ]; then
    echo "Please run this script with sudo access.."
    exit 1
fi

mkdir -p $logs_folder
script_dir=$(dirname "$(realpath "$0")")    # folder where this script lives, saved before cd /app

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

dnf module disable nodejs -y &>> $logs_file
dnf module enable nodejs:24 -y &>> $logs_file
dnf install nodejs -y &>> $logs_file
validate $? "installing nodejs:24"

id roboshop &>> $logs_file
if [ $? -ne 0 ]; then
   useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>> $logs_file
   validate $? "creating system user"
else
   echo -e "$(timestamp) [INFO] system user roboshop already exist...${Y}SKIPPING${N}" | tee -a $logs_file
fi

mkdir -p /app
validate $? "creating app directory"

curl -L -o /tmp/catalogue.zip https://raw.githubusercontent.com/daws-92s/roboshop-documentation/refs/heads/main/artifacts/catalogue-v4.zip &>> $logs_file
validate $? "Downloading catalogue"

cd /app
rm -rf /app/*    # NEW: remove old code so unzip doesn't ask "replace?"
unzip /tmp/catalogue.zip &>> $logs_file
validate $? "unzipping catalogue"

npm install &>> $logs_file
validate $? "installing dependencies"

cp $script_dir/catalogue.service /etc/systemd/system/catalogue.service    # FIXED: copy first, full path
validate $? "copying catalogue service"

sed -i "s/DOMAIN_NAME/$domain_name/" /etc/systemd/system/catalogue.service    # FIXED: closing / and ed
validate $? "updating domain name in catalogue service"

systemctl daemon-reload &>> $logs_file
systemctl enable catalogue &>> $logs_file
systemctl start catalogue &>> $logs_file
validate $? "starting and enabling catalogue"

cp $script_dir/mongo.repo /etc/yum.repos.d/mongo.repo    # NEW: MongoDB client + load products
validate $? "adding mongo repo"

dnf install mongodb-mongosh -y &>> $logs_file
validate $? "installing mongodb client"

product_count=$(mongosh --host mongodb.$domain_name --quiet --eval 'db.getSiblingDB("catalogue").products.countDocuments()' 2>> $logs_file)    # NEW: load products only once
validate $? "connecting to mongodb"

if [ "$product_count" -eq 0 ]; then
    mongosh --host mongodb.$domain_name </app/db/master-data.js &>> $logs_file
    validate $? "loading catalogue products"
else
    echo -e "$(timestamp) [INFO] products are already loaded...${Y}SKIPPING${N}" | tee -a $logs_file
fi

systemctl restart catalogue &>> $logs_file    # NEW: restart so catalogue picks up every change
validate $? "restarting catalogue"

echo "$(timestamp) [INFO] script completed in  $SECONDS seconds" | tee -a $logs_file
echo "$(timestamp) [INFO] ==== Script completed execution ======" | tee -a $logs_file
```

</details>

---

## Run + result

![catalogue.service](../images/handson/05-catalogue-service.png)

`/health` → `{"app":"OK","mongo":true}`, `/products` → all **11 products**.

![05-catalogue.sh run, health and products](../images/handson/05-catalogue-run-health-products.png)

## Verify

```bash
systemctl status catalogue                 # active (running)
curl localhost:8080/health                 # {"app":"OK","mongo":true}
curl localhost:8080/products               # 11 products
journalctl -u catalogue -n 20              # app log
```

---

## Problems I hit

| Problem | Cause | Fix |
|---------|-------|-----|
| `cp: cannot stat 'catalogue.service'` | `cp` ran after `cd /app` | `script_dir=$(dirname "$(realpath "$0")")` at the top |
| `cp` still failed | File was saved as `" catalogue.service"` (leading space) | Renamed it |
| `sed: unterminated 's' command` | Missing the 3rd `/` | `s/DOMAIN_NAME/$domain_name/` |
| Re-run looked frozen | `unzip` asked "replace?" with output in the log | `rm -rf /app/*` first |
| 2nd run would load products twice | `master-data.js` ran every time | `countDocuments()` → load only if `0` |
| Re-run ignored a changed service file | `start` on a running service does nothing | `restart` + `validate` at the end |
| Download URL broken | Long line got cut when pasting | `bash -n` + `curl -sI <url>` → 200 |

More: [all problems and fixes](../troubleshooting.md) · [Traffic flow: incoming and outgoing](../traffic-flow-incoming-outgoing.md)

---

## Interview questions

**1. Why `script_dir=$(dirname "$(realpath "$0")")`?**
It saves the script's own folder as a full path before `cd /app`, so the script still finds its files.

**2. Why `sed` the copy and not the repo file?**
The repo file keeps `DOMAIN_NAME`. Git stays clean and the next run works the same.

**3. Why `daemon-reload`?**
systemd caches unit files. After adding or changing one, it must reload them.

**4. Why run the app as `roboshop` and not root?**
If the app is hacked, the attacker only gets a user with no shell and no root rights.

**5. How did you stop products loading twice?**
Count first with `countDocuments()`; load only if it's 0, else SKIPPING.
