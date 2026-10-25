# 01-mongodb.sh: MongoDB Server

[← Server notes](README.md) · [Project README](../../README.md) · [Scripts walkthrough](../scripts-walkthrough.md)

## What this server does

**MongoDB** stores the **products** (catalogue) and the **users and orders** (user).

| Fact | Value |
|------|-------|
| Server | `roboshop-mongodb` (RHEL 9, t3.micro) |
| Software | MongoDB 7.0 (from `mongo.repo`) |
| Port | 27017 |
| Called by | catalogue, user |
| SG inbound | 27017 from `roboshop-catalogue`, `roboshop-user` |
| Config file I change | `/etc/mongod.conf` → `bindIp: 0.0.0.0` |
| Files used | `01-mongodb.sh`, `mongo.repo` |
| Log | `/var/log/roboshop/01-mongodb.sh.log` |

---

## Steps the script does

1. Check I'm root
2. Add the MongoDB 7.0 repo
3. Install MongoDB
4. Enable + start `mongod`
5. Change listen address `127.0.0.1` → `0.0.0.0`
6. Restart `mongod` so it reads the new config

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
validate(){ ... }
```

**What it does:** settings, root check, log folder, `validate` helper. Explained in the [server notes index](README.md#the-common-part-top-of-every-script). (This first script has no `timestamp` yet.)

### 5. Add the MongoDB repo

```bash
cp mongo.repo /etc/yum.repos.d/mongo.repo
validate $? "Adding mongo repo"
```

**What it does:** copies my `mongo.repo` into dnf's repo folder.
**Why:** MongoDB isn't in RHEL's repos. The file tells `dnf` where to download MongoDB **7.0** (8.0 crashes on this AMI).

```ini
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
enabled=1
gpgcheck=0
```

### 6. Install MongoDB

```bash
dnf install mongodb-org -y &>> $logs_file
validate $? "Install MongoDB"
```

**What it does:** installs the MongoDB server and tools. `-y` answers "yes" automatically.

### 7. Start it

```bash
systemctl enable mongod &>> $logs_file
systemctl start mongod &>> $logs_file
validate $? "Enable and start MongoDB"
```

**What it does:** `enable` = start on every boot, `start` = start now. The service is called **`mongod`**.

### 8. Open it to other servers

```bash
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf
validate $? "Updating remote connections to MongoDB"
```

**What it does:** in `/etc/mongod.conf`, changes `bindIp: 127.0.0.1` → `bindIp: 0.0.0.0`.
**Why:** `127.0.0.1` = only this server can connect. catalogue and user are other servers.

### 9. Restart to apply

```bash
systemctl restart mongod
validate $? "Restarting MongoDB"
```

**What it does:** stops and starts MongoDB so it reads the new config.
**Why:** the config is read only at start, and `start` does nothing on a running service.

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

echo "Script started execution at $(date +"%F %T")" &>> $logs_file

validate(){
    if [ $1 -ne 0 ]; then
        echo -e "${2}..${R}FAILED${N}" | tee -a $logs_file
        exit 1
    else
        echo -e "${2}..${G}SUCCESS${N}" | tee -a $logs_file
    fi
}


cp mongo.repo /etc/yum.repos.d/mongo.repo
validate $? "Adding mongo repo"

dnf install mongodb-org -y &>> $logs_file
validate $? "Install MongoDB"

systemctl enable mongod &>> $logs_file
systemctl start mongod &>> $logs_file
validate $? "Enable and start MongoDB"

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf
validate $? "Updating remote connections to MongoDB"

systemctl restart mongod
validate $? "Restarting MongoDB"
```

</details>

---

## Run + result

```
Adding mongo repo..SUCCESS
Install MongoDB..SUCCESS
Enable and start MongoDB..SUCCESS
Updating remote connections to MongoDB..SUCCESS
Restarting MongoDB..SUCCESS
```

## Verify

```bash
systemctl status mongod          # active (running)
ss -tlnp | grep 27017            # 0.0.0.0:27017  ← open to other servers
grep bindIp /etc/mongod.conf     # bindIp: 0.0.0.0
```

---

## Watch out for

| Problem | Cause | Fix |
|---------|-------|-----|
| MongoDB 8.0 crashes on this AMI | Version not compatible with the practice AMI | Use the **7.0** repo |
| `cp: cannot stat 'mongo.repo'` | This first script uses a relative path | Run it from inside the repo folder (later scripts use `script_dir`) |
| `Unit mongodb.service not found` | Wrong service name | It's `mongod` |
| Others get `connection refused` | Still on `127.0.0.1` | `sed` bindIp + **restart** |

---

## Interview questions

**1. Why change `bindIp` to `0.0.0.0`?**
By default MongoDB only listens on `127.0.0.1`, so only the server itself can connect. `0.0.0.0` lets catalogue and user connect; the SG decides who's actually allowed.

**2. Why restart after `sed`?**
The config file is read only when the service starts.

**3. Why a separate repo file?**
MongoDB isn't in the RHEL repos. The `.repo` file tells `dnf` where to download it.
