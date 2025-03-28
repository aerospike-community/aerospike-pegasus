#!/bin/bash
sudo apt update
sudo apt install -y openjdk-22-jdk
sudo apt install -y maven

cd /root
git clone https://github.com/aerospike-community/aerospike-perseus.git
cd /root/aerospike-perseus
git pull
mvn package

echo "Setup of Perseus is finished!"