# Problems I Hit and Fixes

[← Back to project README](../README.md) · [Scripts walkthrough](scripts-walkthrough.md) · [Debugging guide](debugging-guide.md)

| # | Problem | Cause | Fix |
|---|---------|-------|-----|
| 1 | Old AMI `ami-0220d79f3f480ecf5` not found | The practice AMI was rebuilt; old ID deregistered | New `Redhat-9-DevOps-Practice` = `ami-0055977a6e828a4f4`. Check by name before using an ID |
| 2 | SG ID from class (`sg-043444d…`) not found | That ID belongs to the trainer's account | Use **my own** SGs, or SG **names** (`--security-groups`) |
| 3 | `sh roboshop.sh` printed nothing | No server names given → `$@` empty → loop ran 0 times | `bash roboshop.sh mongodb` |
| 4 | Variable printed empty | Bash names are case-sensitive: set `INSTANCE_ID`, used `$instance_id` | Use the same name everywhere |
| 5 | `r53_recod: command not found` (trainer's live code) | Spaces around `=` | `r53_record_name="..."`, no spaces |
| 6 | Route 53 got literal `$IP` (trainer's live code) | Variables don't expand inside single quotes | `"'$IP'"` (close the quote around the variable) |
| 7 | `ERROR 1045 Access denied for 'root'@'localhost'` after 03-mysql.sh said SUCCESS | `mysql_secure_installation --set-root-pass` set the password only on `root@'%'`; `root@localhost` stayed empty (proved with `authentication_string=''` in `mysql.user`) | `ALTER USER 'root'@'localhost' IDENTIFIED BY 'RoboShop@1';` + a login-check step in the script |
| 8 | `script completed in  seconds` (empty) | Used `$seconds`; the built-in is `$SECONDS` (case-sensitive) | `$SECONDS` |
| 9 | 2nd run of 04-rabbitmq.sh would fail at `add_user` | User already exists → non-zero exit → validate stops | Check first: `rabbitmqctl list_users \| grep -qw roboshop`, else SKIPPING |
| 10 | `sed: unterminated 's' command` | `"s/DOMAIN_NAME/$domain_name"`: missing the 3rd `/` | `"s/DOMAIN_NAME/$domain_name/"` |
| 11 | `cp catalogue.service` → No such file | Ran after `cd /app`; the file is in the script folder | `script_dir=$(dirname "$(realpath "$0")")` at the top, `cp $script_dir/catalogue.service ...` |
| 12 | `cp` still couldn't find `catalogue.service` | File was saved as `" catalogue.service"` (leading space in the name) | `mv " catalogue.service" catalogue.service` |
| 13 | Download step would fail | Long lines got cut off when pasted (`.../refs/he-v4.zip`, `$logs_f`) | Check line ends; `bash -n script.sh` for syntax; `curl -sI <url>` → 200 |
| 14 | Typing in VS Code deleted the next letters | Overtype mode (`OVR` in the status bar) | Press the **Insert** key |
| 15 | Script looked frozen at `dnf install` | Output goes to the log; dnf was refreshing repo metadata | `tail -f /var/log/roboshop/<script>.log` in a 2nd session |
| 16 | 2nd run of 05-catalogue.sh would load products twice | `master-data.js` runs every time | Count first with `countDocuments()`; load only if `0`, else SKIPPING |
| 17 | Re-run didn't pick up a changed service file | `systemctl start` does nothing on a running service | End with `systemctl restart catalogue` + `validate` |

**Find the latest AMI by name:**
```bash
aws ec2 describe-images --owners 973714476881 \
  --filters "Name=name,Values=Redhat-9-DevOps-Practice" \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text
```

> Use `bash`, not `sh`: on Ubuntu, `sh` is **dash**, a smaller shell.
