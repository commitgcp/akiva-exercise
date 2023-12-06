#!/bin/bash

set -e
exec > /tmp/debug-my-script.txt 2>&1

useradd -m appadmin
mkhomedir_helper appadmin
passwd -d appadmin
sleep 20
sudo apt update
sudo apt -y install curl
su - appadmin -c "touch ~/.bash_profile"
su - appadmin -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash"
sleep 5
sudo apt -y install npm
su - appadmin -c "git clone https://github.com/commitgcp/okta-nodejs-postgres-weight-tracker-example.git ~/app/"
su - appadmin -c "cd ~/app/ && npm install"
sleep 20
su - appadmin -c "wget https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.0.0/cloud-sql-proxy.linux.amd64 \
-O cloud-sql-proxy && chmod +x cloud-sql-proxy && ./cloud-sql-proxy --private-ip akiva-sandbox:us-central1:private-instance-0d555f4a &"
su - appadmin -c ". ~/.nvm/nvm.sh && nvm install 12 && sleep 10 && cd ~/app && npm run initdb && npm run dev"
