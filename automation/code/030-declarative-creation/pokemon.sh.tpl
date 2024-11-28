#!/bin/sh
 
sudo apt update
sudo apt install awscli openjdk-17-jre-headless -y
wget https://github.com/ciberado/pokemon-java/releases/download/v2.0.0/pokemon-2.0.0.jar
java -jar -Dserver.port=${port} pokemon-2.0.0.jar