# jenkins-lts-custom
Helm Chart and docker image for jenkins with custom plugins.
Used primarily at out site.

## How to use
Possible use cases for other sites:
- reuse as is in case your need of plugins is exactly like ours
- clone/fork the repo and modify plugin-requests.txt to match your needs
## how it works
plugins-request.txt contains the list of requested plugins, the automatism
will add any dependency plugins needed.

the github action described in .github/workflow/jenkins-lts-custom.yaml will
do the magic:
- update to latest Jenkins helm chart release
- updating to jenkins version used in latest Jenkins helm chart release
- Update all plugins to latest version. This applies to plugins explicitly
  requested in plugins-request.txt and all dependent plugins
- if something changed, create a new version of the helm chart

## Versioning compliant with semver2
### new Patch releases are created automatically by github actions
the automatism in .github/workflow/jenkins-lts-custom.yaml will create new patch
versions major.minor.(patch+1) if any updates appear on our dependent sites:
- Helm Repo at https://charts.jenkins.io
- Any Plugin update (incl. dependencies)
  Plugin updates are detected by running jenkins-plugin-cli inside the
  target jenkins container

### Manual Patch releases
On push to github with no update of version in charts/jenkins-lts-custom/Chart.yaml
the github action will incorporate updates from dependent sites if any (see above)
and release a new patch version

### Manual Major or Minor releases
New major or minor versions MAJOR.MINOR.0 are created manually by editing
charts/jenkins-lts-custom/Chart.yaml and pushing.

### tagging
Tagging should only be done by github action, manual pushing a tag will
probably result in the automatism stopping or creating unpredictable results

# Legal, copyright etc.
This project has been inspired by jenkins-infra/docker-jenkins-lts, that does
as of today not contain any copyright or license information

The project is available under MIT license, (C) Stefan Schallenberg
