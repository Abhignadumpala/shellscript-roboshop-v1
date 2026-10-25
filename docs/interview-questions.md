# Interview Questions: RoboShop Shell Scripts

[← Back to project README](../README.md) · [Scripts walkthrough](scripts-walkthrough.md)

**1. What does `$?` hold?**

The exit code of the last command. `0` = success, anything else = failure.

**2. What does `$0` hold? And `$@`, `$#`?**

`$0` = the script's name. `$@` = all arguments. `$#` = the number of arguments.

**3. How do you check that a script runs as root?**

`id -u` returns `0` for root: `if [ $(id -u) -ne 0 ]; then echo "run with sudo"; exit 1; fi`.

**4. What does `&>>` do?**

Appends both normal output and errors to a file. `>>` appends only normal output; `&>` overwrites.

**5. What does `tee -a` do?**

Shows output on screen **and** appends it to a file at the same time.

**6. Why use a validate function?**

To check every step's exit code in one reusable place, print SUCCESS / FAILED, and stop at the first failure instead of continuing with a broken setup.

**7. Why don't variables work in `'...$IP...'`?**

Single quotes keep text literal. Use double quotes, or close the single quote around the variable: `'"Value": "'$IP'"'`.

**8. What is UPSERT in Route 53?**

Update the record if it exists, create it if it doesn't. Safe to run again and again.

**9. Why does frontend get a public IP record and others private?**

Users reach frontend from the internet. Backend servers talk to each other inside the VPC, so private IPs are enough and safer.

**10. What happens to IPs when an EC2 instance is stopped and started?**

The private IP stays the same; the public IP changes (unless it's an Elastic IP).

**11. Why attach a common SG to all instances?**

Shared rules (like SSH from my IP) live in one place. One change updates every server.

**12. What is `sed -i`?**

sed = Stream EDitor. `-i` = in-place: saves the change into the file. Without it, sed only prints the result.

**13. Where would you use Terraform and Ansible instead of these scripts?**

Terraform to create servers, SGs and DNS (`roboshop.sh`); Ansible to install and configure software (`01-mongodb.sh`).

**14. What is an idempotent script? Give an example.**

A script that gives the **same result no matter how many times I run it or retry it**: no failures, nothing duplicated. Examples: `id roboshop` before `useradd`, `rabbitmqctl list_users | grep -qw roboshop` before `add_user`, `countDocuments()` before loading products, `mkdir -p`, `rm -rf /app/*` before unzip. A 2nd run prints SKIPPING. If a run fails halfway, I fix it and run again without cleanup.

**15. What does `grep -qw` do?**

`-q` = quiet, print nothing and only set the exit code (0 = found). `-w` = match the whole word only.

**16. What is `$SECONDS`?**

A built-in bash variable: seconds since the script started. Used to print the run time. Variable names are case-sensitive, so `$seconds` is empty.

**17. A group of commands has one `validate $?` at the end. What's the risk?**

`$?` holds only the last command's exit code. If an earlier command fails (e.g. `dnf module enable redis:7`) and the last one succeeds, the script says SUCCESS with the wrong setup.

**18. `mysql_secure_installation` said success but `mysql -uroot -p...` gives Access denied. Why?**

MySQL users are user + host. `--set-root-pass` set the password on `root@'%'` but left `root@localhost` empty. Fix with `ALTER USER 'root'@'localhost' IDENTIFIED BY '...'` and add a login check to the script.

**19. Why use `script_dir=$(dirname "$(realpath "$0")")` at the top of a script?**

The script later runs `cd /app`; relative paths like `catalogue.service` would then look in `/app`. This saves the script's own folder as a full path. `$PWD` only works if you run it from that folder; `realpath "$0"` works from anywhere.

**20. Why put a `DOMAIN_NAME` placeholder in the service file and replace it with sed?**

The domain stays in one variable, the file uses a DNS name instead of an IP, and sed edits the copied file in `/etc/systemd/system/`, so the repo file stays reusable.

**21. Why `systemctl daemon-reload` after copying a service file?**

systemd caches unit files. `daemon-reload` makes it read the new or changed file before `enable`/`start`.

**22. Why `rm -rf /app/*` before `unzip`?**

On a re-run unzip asks "replace?" and waits. With output redirected to a log, the script looks frozen. Cleaning first makes the step re-runnable.


**23. How do you stop a script from loading the same data twice?**

Count first: `mongosh --eval '...products.countDocuments()'`. If it's `0`, load `master-data.js`; otherwise print SKIPPING. Now a re-run doesn't duplicate products.

**24. Why end an app script with `systemctl restart` and not `start`?**

`start` does nothing if the service is already running, so on a re-run the new code or config is ignored. `restart` always stops and starts it, so every change is loaded. Then `validate $?` confirms it came back up.
