#!/bin/bash
#
# generate helm chart under nafets227/jenkins-lts-custom name
# starting from jenkinsci/helm-charts that are in submodule with same name
#

DIR=$(dirname $0)/charts/jenkins-lts-custom &&

annImages=$(
	yq -r ".annotations.\"artifacthub.io/images\"" $DIR/Chart.yaml
	) &&
imgVer=$(yq -r ".[]
	| select(.name == \"jenkins\")
	| .image
	" - <<<"$annImages"
	) &&
imgVer=${imgVer%%*:} &&
annImages=$(yq -Y ".
	| ( .[]
		 | select(.name == \"jenkins\")
		 | .image )
	|=\"ghcr.io/nafets227/jenkins-lts-custom:$imgVer\"
	" - <<<"$annImages"
	) &&
annImages=$(jq -aRs <<<"$annImages") &&

yq -Y -i ".
	| .name |= \"jenkins-lts-custom\"
	| .home |= \"https://github.com/nafets227/jenkins-lts-custom\"
	| .sources += [ \"https://github.com/nafets227/jenkins-lts-custom\" ]
	| .maintainers |= [{\"name\": \"nafets227\", \"email\": \"nafets227@users.noreply.github.com\"}]
	| .annotations.\"artifacthub.io/links\" |= \"https://github.com/nafets227/jenkinsci-lts-custom/helm-charts/tree/main/charts/jenkins\"
	| .annotations.\"artifacthub.io/images\" |= $annImages
	" \
	$DIR/Chart.yaml &&

yq -Y -i "
	.controller.image |= \"ghcr.io/nafets227/jenkins-lts-custom\"
	" \
	$DIR/values.yaml &&

true || exit 1

exit 0
