# roboshop.sh: Create Servers + DNS Records

[← Project README](README.md) · [Common part of every script](00-common-part.md) · [Scripts walkthrough](docs/scripts-walkthrough.md)

## What it does

Runs on **my laptop**. For every name I give it, it:

1. Creates an **EC2 instance** with the right security groups and Name tag
2. Waits until it's **running**
3. Gets its **IP**: private for backends, public for frontend
4. Creates or updates the **Route 53** record (`mongodb.abhignadevops.store` → IP)

```bash
bash roboshop.sh mongodb redis mysql rabbitmq catalogue
```

| Fact | Value |
|------|-------|
| Runs on | My laptop (needs AWS CLI + credentials) |
| AMI | `Redhat-9-DevOps-Practice` (`ami-0055977a6e828a4f4`) |
| Type | `t3.micro` |
| SGs | `roboshop-common` (SSH) + `roboshop-<name>` |
| DNS | Route 53 zone `abhignadevops.store` |

---

## The code, block by block

### 1. Settings

```bash
ami_id="ami-0055977a6e828a4f4"        # Redhat-9-DevOps-Practice
instance_type="t3.micro"
hosted_zone_id="<my-hosted-zone-id>"
domain_name="abhignadevops.store"
```

**What it does:** the values every server uses: which image (AMI), which size, which Route 53 zone, which domain.
**Why:** change them once here, not in every command.

### 2. One loop round per server name

```bash
for instance in $@
do
    echo "Creating instance: $instance"
    ...
done
```

**What it does:** `$@` = every name I typed. `bash roboshop.sh mongodb redis` → the loop runs twice: `instance=mongodb`, then `instance=redis`.

### 3. Create the server

```bash
instance_id=$(aws ec2 run-instances \
        --image-id $ami_id \
        --instance-type $instance_type \
        --security-groups "roboshop-common" "roboshop-$instance" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
        --query 'Instances[0].InstanceId' \
        --output text
)
```

**What it does:** creates one EC2 instance and saves its ID (e.g. `i-0b336bf4b51e709ea`).

| Option | Meaning |
|--------|---------|
| `--security-groups "roboshop-common" "roboshop-$instance"` | 2 SGs: SSH (common) + the server's own rules |
| `--tag-specifications ... Value=roboshop-$instance` | Name in the console: `roboshop-mongodb` |
| `--query 'Instances[0].InstanceId' --output text` | Print only the ID, not the whole JSON |

### 4. Wait until it's running

```bash
aws ec2 wait instance-running --instance-ids $instance_id
```

**What it does:** pauses until the server is `running`.
**Why:** right after launch the IP can still be empty.

### 5. Get the right IP

```bash
if [ $instance != "frontend" ]; then
    IP=$( aws ec2 describe-instances --instance-ids $instance_id \
        --query 'Reservations[].Instances[].PrivateIpAddress' --output text )
    r53_record_name="$instance.$domain_name"
else
    IP=$( aws ec2 describe-instances --instance-ids $instance_id \
        --query 'Reservations[].Instances[].PublicIpAddress' --output text )
    r53_record_name="$domain_name"
fi
```

**What it does:**

| Server | IP | DNS name |
|--------|----|----------|
| any backend (mongodb, catalogue…) | **private** | `mongodb.abhignadevops.store` |
| frontend | **public** | `abhignadevops.store` |

**Why:** backends are only called inside the VPC; only the frontend is reached from the internet.

### 6. Create / update the DNS record

```bash
aws route53 change-resource-record-sets \
--hosted-zone-id $hosted_zone_id \
--change-batch '{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "'$r53_record_name'",
            "Type": "A",
            "TTL": 1,
            "ResourceRecords": [{"Value": "'$IP'"}]
        }
    }]
}'
```

**What it does:** writes `mongodb.abhignadevops.store → 172.31.x.x` in Route 53.

| Part | Meaning |
|------|---------|
| `UPSERT` | **UP**date if it exists, in**SERT** if not: safe to re-run |
| `"Type": "A"` | name → IPv4 address |
| `"TTL": 1` | cached for 1 second, so a new IP is used almost at once |
| `"'$IP'"` | close the single quote so bash puts the real IP in |

<details>
<summary><b>Full script in one piece</b> (click to open)</summary>

```bash
#!/bin/bash

##############################################################
# RoboShop: create EC2 instances + update Route 53 records
# Usage: bash roboshop.sh mongodb redis mysql rabbitmq catalogue
##############################################################

ami_id="ami-0055977a6e828a4f4"        # Redhat-9-DevOps-Practice
instance_type="t3.micro"
hosted_zone_id="Z0720368AL7KSN1O4AZ2"
domain_name="abhignadevops.store"

for instance in $@
do
    echo "Creating instance: $instance"

    instance_id=$(aws ec2 run-instances \
            --image-id $ami_id \
            --instance-type $instance_type \
            --security-groups "roboshop-common" "roboshop-$instance" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query 'Instances[0].InstanceId' \
            --output text
    )

    echo "$instance ID: $instance_id"

    # wait until running, so the IP is ready
    aws ec2 wait instance-running --instance-ids $instance_id

    if [ $instance != "frontend" ]; then
        IP=$( aws ec2 describe-instances --instance-ids $instance_id \
            --query 'Reservations[].Instances[].PrivateIpAddress' --output text
        )
        r53_record_name="$instance.$domain_name"
    else
        IP=$( aws ec2 describe-instances --instance-ids $instance_id \
            --query 'Reservations[].Instances[].PublicIpAddress' --output text
        )
        r53_record_name="$domain_name"
    fi

    echo "$instance IP: $IP"

    # update R53 record
    # '...'$var'...' -> close the single quote around each variable so bash replaces it

    aws route53 change-resource-record-sets \
    --hosted-zone-id $hosted_zone_id \
    --change-batch '{
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                "Name": "'$r53_record_name'",
                "Type": "A",
                "TTL": 1,
                "ResourceRecords": [{"Value": "'$IP'"}]
                }
            }
        ]
    }'

    echo "DNS updated: $r53_record_name -> $IP"
done
```

</details>

---

## How I ran it

```bash
bash roboshop.sh mongodb
```
```
Creating instance: mongodb
mongodb ID: i-0b336bf4b51e709ea
mongodb IP: 172.31.0.236
DNS updated: mongodb.abhignadevops.store -> 172.31.0.236
```

![roboshop.sh catalogue](docs/images/handson/05-roboshop-sh-catalogue.png)

---

## Problems I hit

| Problem | Cause | Fix |
|---------|-------|-----|
| `InvalidAMIID.NotFound` | The practice AMI was rebuilt; the old ID is gone | Look up the latest ID **by name** with `aws ec2 describe-images` |
| SG ID not found | I copied an SG ID from another account | Use **my own** SG names |
| `bash roboshop.sh` printed nothing | No names given → `$@` empty → loop ran 0 times | `bash roboshop.sh mongodb` |
| Route 53 got the literal text `$IP` | Variable inside single quotes | `"'$IP'"` |
| `r53_record: command not found` | Spaces around `=` | `name="value"`, no spaces |
| `-e` printed on screen | Ran with `sh` (dash on Ubuntu) | Run with `bash` |

---

## Interview questions

**1. Why `wait instance-running` before getting the IP?**
Right after `run-instances` the instance is `pending` and the IP can be empty. Waiting makes the DNS record correct.

**2. Why private IP for backends and public IP for frontend?**
Backends are only called by other servers in the VPC. Only the frontend is reached from the internet.

**3. What is UPSERT?**
Update the record if it exists, insert it if not. The script is safe to run again when an IP changes.
