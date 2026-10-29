# RoboShop: 3-Tier Microservices on AWS, Automated with Shell Scripts

> Deploying the **RoboShop** e-commerce app (frontend, 6 microservices, 4 databases) on **AWS EC2** with **Bash** and the **AWS CLI**. One script creates the servers and DNS records, and one script per component installs and configures that service, with logging, validation and safe re-runs.

📖 **Every script explained block by block, with hands-on screenshots and troubleshooting:** [roboshop-project-v1-shellscript-notes](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes)

![RoboShop architecture](images/architecture.png)

![Who calls whom: every RoboShop server, its port and who it connects to](images/who-calls-whom.svg)

![App servers 06–08: the connections I checked](images/06-08-app-connections-verified.png)

---

## What this project does

| Without scripts | With this repo |
|-----------------|----------------|
| Click in the AWS console to create each server, copy IPs into DNS by hand | `bash roboshop.sh mongodb redis ...` creates the servers **and** the Route 53 records |
| SSH in and type 10–20 commands per server | `bash 02-redis.sh` installs and configures the whole component |
| Easy to miss a step; no record of what ran | Every step is **validated** (SUCCESS / FAILED) and **logged** with timestamps |
| Running twice breaks things | Scripts are **idempotent**: a re-run SKIPS what already exists |
| Manual build: **4–5 hours** | With scripts: **about 2 hours** |

---

## Tech stack

| Area | Used |
|------|------|
| Cloud | AWS EC2 (`t3.micro`, RHEL 9), Route 53, Security Groups |
| Automation | Bash, AWS CLI (`run-instances`, `wait`, `describe-instances`, `change-resource-record-sets`) |
| Web / proxy | Nginx (reverse proxy for `/api/*`) |
| App services | Node.js 24, Java, Python, Go |
| Databases / queue | MongoDB 7.0, Redis 7, MySQL 8.4, RabbitMQ |
| Linux | `dnf` modules, systemd units, `sed`, users, logs |

---

## Scripts

| Script | Runs on | What it does | Run time | Explained |
|--------|---------|--------------|----------|-----------|
| [roboshop.sh](roboshop.sh) | laptop | Creates EC2 instances + Route 53 records | – | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/00-roboshop) |
| [01-mongodb.sh](01-mongodb.sh) | mongodb | MongoDB 7.0, open to other servers | – | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/01-mongodb) |
| [02-redis.sh](02-redis.sh) | redis | Redis 7, `bind` + `protected-mode` | 21 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/02-redis) |
| [03-mysql.sh](03-mysql.sh) | mysql | MySQL 8.4, root password + login check | 40 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/03-mysql) |
| [04-rabbitmq.sh](04-rabbitmq.sh) | rabbitmq | RabbitMQ + app user (re-run safe) | 36 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/04-rabbitmq) |
| [05-catalogue.sh](05-catalogue.sh) | catalogue | Node.js app, systemd service, products loaded once | 63 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/05-catalogue) |
| [06-user.sh](06-user.sh) | user | Node.js app, sessions in Redis, users in MongoDB | 109 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/06-user) |
| [07-cart.sh](07-cart.sh) | cart | Node.js app, cart in Redis, prices from catalogue | 99 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/07-cart) |
| [08-shipping.sh](08-shipping.sh) | shipping | Java + Maven build, cities loaded into MySQL once | 216 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/08-shipping) |
| [09-payment.sh](09-payment.sh) | payment | Python 3.14 + venv + gunicorn, orders to RabbitMQ | 18 s | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/09-payment) |
| [10-frontend.sh](10-frontend.sh) | frontend | Nginx 1.26 reverse proxy for `/api/*`, `nginx -t` before restart | – | [📖](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/tree/main/10-frontend) |
| dispatch | | | | next |

**Result:** shop live at `http://abhignadevops.store`, all 5 `/api/<service>/health` = 200 from the internet, **3 orders placed end to end**.

Support files: [mongo.repo](mongo.repo) · [rabbitmq.repo](rabbitmq.repo) · [catalogue.service](catalogue.service) · [user.service](user.service) · [cart.service](cart.service) · [shipping.service](shipping.service) · [payment.service](payment.service) · [roboshop.conf](roboshop.conf) (nginx)

---

## Do the lab yourself (step by step)

```
                  ┌──────────► catalogue ──► mongodb
browser ──► frontend (Nginx) ─► user ──────► mongodb, redis
                  ├──────────► cart ───────► redis
                  ├──────────► shipping ───► mysql
                  └──────────► payment ────► rabbitmq
```

### Step 0: What you need

| Need | Why |
|---|---|
| AWS account + **AWS CLI** configured on your laptop (`aws configure`) | `roboshop.sh` creates servers from the laptop |
| A **domain** with a **Route 53 hosted zone** | every server gets a name like `mongodb.<your-domain>` |
| A **RHEL 9** AMI | all scripts use `dnf` + systemd |
| Git on the laptop | clone / fork this repo |

`roboshop.sh` doesn't attach a key pair (I used a practice AMI with password login). With a normal RHEL AMI, add `--key-name <your-key>` to `aws ec2 run-instances` and SSH with `-i <your-key>.pem`.

### Step 1: Fork and set your values

Fork this repo, clone it to your laptop, and change these values to yours:

| File | Variable | Set to |
|---|---|---|
| `roboshop.sh` | `ami_id` | your RHEL 9 AMI ID |
| `roboshop.sh` | `hosted_zone_id` | your Route 53 hosted zone ID |
| `roboshop.sh` | `domain_name` | your domain |
| `05-catalogue.sh` … `10-frontend.sh` (6 scripts) | `domain_name` | your domain |

In v1 every script has its own copy of `domain_name` (that's why v2 moved it into `common.sh`). The `.service` files and `roboshop.conf` use `DOMAIN_NAME`; the scripts replace it on the server, so you don't edit those.

Push your changes (servers clone from **your** fork):
```bash
git add .
git commit -m "Set my AMI, hosted zone and domain"
git push
```

### Step 2: Create the security groups (once)

`roboshop.sh` attaches 2 SGs to each server: `roboshop-common` + `roboshop-<component>`. Create these in the default VPC:

| Security group | Inbound port | Allowed from |
|---|---|---|
| `roboshop-common` | 22 (SSH) | your IP |
| `roboshop-frontend` | 80 | `0.0.0.0/0` (everyone) |
| `roboshop-catalogue` | 8080 | frontend, cart |
| `roboshop-user` | 8080 | frontend, payment |
| `roboshop-cart` | 8080 | frontend, shipping, payment |
| `roboshop-shipping` | 8080 | frontend |
| `roboshop-payment` | 8080 | frontend |
| `roboshop-mongodb` | 27017 | catalogue, user |
| `roboshop-redis` | 6379 | user, cart |
| `roboshop-mysql` | 3306 | shipping |
| `roboshop-rabbitmq` | 5672 | payment |

"Allowed from frontend" = source is the SG `roboshop-frontend`, not an IP, so the rule still works when servers get new IPs.

### Step 3: Create the servers (laptop)

```bash
bash roboshop.sh mongodb redis mysql rabbitmq catalogue user cart shipping payment frontend
```

For each name it creates the EC2 server `roboshop-<name>` and a DNS record:

| Server | DNS record | IP used |
|---|---|---|
| frontend | `<your-domain>` | **public** (for the browser) |
| all others | `<name>.<your-domain>` | **private** (server to server) |

### Step 4: Install each component (on each server)

SSH into each server, clone **your** fork and run that server's script:
```bash
ssh ec2-user@<public-ip>
sudo su -
dnf install git -y            # skip if git is already there
git clone https://github.com/<your-username>/shellscript-roboshop-v1.git
cd shellscript-roboshop-v1
bash 01-mongodb.sh            # the script for this server (table below)
```

Order matters: **databases first, then apps, frontend last.**

| Order | Server | Run |
|---|---|---|
| 1 | roboshop-mongodb | `bash 01-mongodb.sh` |
| 2 | roboshop-redis | `bash 02-redis.sh` |
| 3 | roboshop-mysql | `bash 03-mysql.sh` |
| 4 | roboshop-rabbitmq | `bash 04-rabbitmq.sh` |
| 5 | roboshop-catalogue | `bash 05-catalogue.sh` |
| 6 | roboshop-user | `bash 06-user.sh` |
| 7 | roboshop-cart | `bash 07-cart.sh` |
| 8 | roboshop-shipping | `bash 08-shipping.sh` |
| 9 | roboshop-payment | `bash 09-payment.sh` |
| 10 | roboshop-frontend | `bash 10-frontend.sh` |

Each step prints **SUCCESS** or **FAILED**. On FAILED the script stops; read `/var/log/roboshop/<script>.sh.log` (watch a long step with `tail -f` in a 2nd SSH session).

> **Shipping on a new RHEL 9 server:** newer RHEL crypto packages can make the Java build fail with `X25519MLKEM768`. v1 doesn't have the fix; it's in v2: [`08-shipping.sh`](https://github.com/Abhignadumpala/shellscript-roboshop-v2/blob/main/08-shipping.sh) (`MAVEN_OPTS`) and [`shipping.service`](https://github.com/Abhignadumpala/shellscript-roboshop-v2/blob/main/shipping.service) (`ExecStart`).

### Step 5: Check it works

On the frontend server:
```bash
curl localhost/api/catalogue/health
curl localhost/api/user/health
curl localhost/api/cart/health
curl localhost/api/shipping/health
curl localhost/api/payment/health
```
All should answer with `OK` / `UP`.

### Step 6: Open the shop in the browser

1. Go to `http://<your-domain>`.
2. **Register** a new user and log in.
3. Add a product to the cart.
4. Checkout → choose country and city for shipping.
5. Pay → open **Order history**: your order is there ✅.

### Step 7: Clean up

Terminate all 10 servers so you don't pay for them (EC2 → select → Terminate, or `aws ec2 terminate-instances --instance-ids <ids>`). The SGs and hosted zone can stay for the next run.

---

## Key features

| Feature | How |
|---------|-----|
| **Validation** | `validate $? "<step>"` after each step → SUCCESS, or FAILED and stop |
| **Logging** | Timestamped `[INFO]` / `[ERROR]` lines in `/var/log/roboshop/<script>.log` |
| **Idempotency** | Check before creating (`id roboshop`, `list_users \| grep -qw`, `countDocuments()`, `SELECT COUNT(*)`) → SKIPPING on re-run |
| **DNS, not IPs** | `DOMAIN_NAME` placeholder in each `.service` file, `sed` on the **installed copy** (repo stays clean for `git pull`); Route 53 private records for every backend |
| **Own files after `cd /app`** | `scripts_dir=$(dirname "$(realpath "$0")")` at the top → `cp $scripts_dir/<app>.service ...` |
| **Restart at the end** | `systemctl restart` + `validate`, so every change is loaded |
| **Validate the result** | e.g. MySQL login check after setting the password; `nginx -t` before restarting nginx |
| **Isolated Python libs** | Payment gets its own venv (`/app/.venv`), system Python untouched |

---

## Problems I solved

| Problem | Fix |
|---------|-----|
| MySQL said SUCCESS but `root@localhost` had **no password** | `ALTER USER` + a login-check step |
| Re-runs failed ("user already exists") or loaded data twice | Check first → SKIPPING |
| `cp catalogue.service` failed after `cd /app` | `scripts_dir=$(dirname "$(realpath "$0")")` at the top |
| A typo in a variable name (`script_dir` vs `scripts_dir`) → empty path, no error | Same name everywhere; `grep -n` after every rename (`bash -n` can't catch it) |
| Shipping data: the count query **fails** on the 1st run (no database yet) | No `validate` after the count; load if the result is empty or `0` |
| Redis refused other servers | Change **both** `bind` and `protected-mode` |
| Re-run ignored a changed service file | `restart`, not `start` |
| Payment needs Python ≥ 3.10, RHEL 9 ships 3.9 | `python3.14` next to it + a venv |
| Payment `/health` → `rabbitmq:false` once, then `true` | Idle connection had dropped; the check reconnects. Check twice before debugging |
| Renamed a script, old file stayed on GitHub | `git rm` the old name; use `git mv` next time |

All problems and fixes: [troubleshooting](https://github.com/Abhignadumpala/roboshop-project-v1-shellscript-notes/blob/main/docs/troubleshooting.md)

---

## What's next

- [x] `06-user.sh`, `07-cart.sh`, `08-shipping.sh`
- [x] `09-payment.sh`, `10-frontend.sh`: 3 orders placed end to end
- [ ] `11-dispatch.sh`
- [ ] Shared functions in `common.sh`
- [ ] Move to **Git + CI/CD**: tests and automatic deploys on every push
