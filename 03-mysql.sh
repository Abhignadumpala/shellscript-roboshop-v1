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