FROM jenkins/jenkins:2.375.1-jdk11

COPY plugins.yaml /usr/share/jenkins/ref/plugins.yaml
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.yaml --verbose
