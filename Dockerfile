FROM jenkins/jenkins:2.346.3-jdk11

COPY plugins.yaml /usr/share/jenkins/ref/plugins.yaml
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.yaml --verbose
