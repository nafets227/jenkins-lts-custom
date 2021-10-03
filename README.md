# jenkins-lts-custom
docker image containing the latest jenkins lts release and plugins used at our site

## How to use
Currently, this repo is not directly intended to used by anybody else. Instead, you are
welcome to understand the concept and copy it into your own project.

## how it works
plugins-request.txt contains the list of requested plugins, the automatism will add any 
dependency plugins needed.

the github action described in .github/workflow/jenkins-lts-custom.yaml will do the magic:
- update to latest Jenkins LTS release
- Update any plugins needed, based on plugins-request.txt
- if something changes, create a new version of the docker image
