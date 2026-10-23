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
script_dir=$PWD    # NEW: remember the script folder before cd /app

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
dnf install mongodb-mongosh -y &>> $logs_file
validate $? "installing mongodb client"

mongosh --host mongodb.$domain_name </app/db/master-data.js &>> $logs_file
validate $? "loading catalogue products"

echo "$(timestamp) [INFO] script completed in  $SECONDS seconds" | tee -a $logs_file
echo "$(timestamp) [INFO] ==== Script completed execution ======" | tee -a $logs_file