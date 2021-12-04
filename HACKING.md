# hacking of nafets227/jenkins-lts-custom
As you can read in README.md, 
the github action described in .github/workflow/jenkins-lts-custom.yaml will
do the magic:
- update to latest Jenkins helm chart release
- updating to jenkins version used in latest Jenkins helm chart release
- Update all plugins to latest version. This applies to plugins explicitly
  requested in plugins-request.txt and all dependent plugins
- if something changed, create a new version of the helm chart

# Versioning compliant with semver2
This project uses semver v2 (https://semver.org) for namings its releases. 
Remember that the versions are versions of this project and are not the same
as the jenkins helm chart version or jenkins software version.

tagging in git is done with a leading "v", e.g. v1.0.0

## new Patch releases are created automatically by github actions
the automatism in .github/workflow/jenkins-lts-custom.yaml will create new patch
versions major.minor.(patch+1) if any updates appear on our dependent sites:
- Helm Repo at https://charts.jenkins.io
- Any Plugin update (incl. dependencies)
  Plugin updates are detected by running jenkins-plugin-cli inside the
  target jenkins container

## Manual Patch releases
On push to github with no update of version in charts/jenkins-lts-custom/Chart.yaml
the github action will incorporate updates from dependent sites if any (see above)
and release a new patch version

## Manual Major or Minor releases
New major or minor versions MAJOR.MINOR.0 are created manually by editing 
charts/jenkins-lts-custom/Chart.yaml and pushing.

# tagging
Tagging should only be done by github action, manual pushing a tag will 
probably result in the automatism stopping or creating unpredictable results

# updating github actions by dependabot
dependabot is configured to auto-update actions used in github actions.

