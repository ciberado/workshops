#!/bin/sh

export SERVER_PORT=8080
 
sudo apt update
sudo apt install awscli openjdk-17-jre-headless -y
wget https://github.com/ciberado/pokemon-java/releases/download/v2.0.0/pokemon-2.0.0.jar
java -jar -Dserver.port=$SERVER_PORT pokemon-2.0.0.jar
