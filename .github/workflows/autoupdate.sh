#!/bin/bash
#
# generate helm chart under nafets227/jenkins-lts-custom name
# starting from jenkinsci/helm-charts that are in submodule with same name
#

##### helmupdate #############################################################
function patchHelm {
	local DIR annImages imgVer orighelmver annImages 
	# global origimage
	DIR=charts/jenkins-lts-custom

	annImages=$(
		yq -r ".annotations.\"artifacthub.io/images\"" $DIR/Chart.yaml
		) &&
	imgVer=$(yq -r ".[]
		| select(.name == \"jenkins\")
		| .image
		" - <<<"$annImages"
		) &&
	imgVer=${imgVer%%*:} &&
	origimage=$(
		helm template -g $DIR \
			| yq -r ".
				| select( .kind == \"StatefulSet\" )
				| .spec.template.spec.containers[]
				| select( .name == \"jenkins\" )
				| .image
				"
		) &&
	orighelmver=$(yq -r ".version" $DIR/Chart.yaml) &&
	annImages=$(yq -Y ".
		| ( .[]
			| select(.name == \"jenkins\")
			| .image )
		|=\"ghcr.io/nafets227/jenkins-lts-custom:$ouractver\"
		" - <<<"$annImages"
		) &&
	annImages=$(jq -aRs <<<"$annImages") &&

	yq -Y -i ".
		| .name |= \"jenkins-lts-custom\"
		| .version |= \"$ouractver\"
		| .home |= \"https://github.com/nafets227/jenkins-lts-custom\"
		| .sources += [ \"https://github.com/nafets227/jenkins-lts-custom\" ]
		| .maintainers |= [{\"name\": \"nafets227\", \"email\": \"nafets227@users.noreply.github.com\"}]
		| .annotations.\"artifacthub.io/links\" |= \"https://github.com/nafets227/jenkinsci-lts-custom/helm-charts/tree/main/charts/jenkins\"
		| .annotations.\"artifacthub.io/images\" |= $annImages
		| .annotations.\"nafets227.github.com/basechart\" |= \"$orighelmver\"
		| .annotations.\"nafets227.github.com/baseimage\" |= \"$origimage\"
		" \
		$DIR/Chart.yaml &&

	yq -Y -i ". 
		| .controller.image |= \"ghcr.io/nafets227/jenkins-lts-custom\"
		| .controller.tag |= \"\${.chart.version}\"
		" \
		$DIR/values.yaml &&

	sed -i -e "s|FROM .*|FROM $origimage|" Dockerfile &&

	true || return 1

	return 0
}

##### findLatestHelm #########################################################
function findLatestHelm {
	# Analyse Jenkins Helm chart versions (actual and latest from internet)
	# get latest version from helm chart repository
	local helmchartjson
	helmchartjson=$(curl https://charts.jenkins.io/index.yaml 2>/dev/null |
		yq '.entries.jenkins | max_by(.version | split("."))'
		) &&
	helmver=$(jq -r '.version' - <<<$helmchartjson) &&
	helmurl=$(jq -r '.urls[0]' - <<<$helmchartjson) &&
	# as described in https://github.com/helm/helm/issues/7314 only first value of urls

	helmactver=$(yq -r '.annotations."nafets227.github.com/basechart"' \
		charts/jenkins-lts-custom/Chart.yaml) &&
	ouractver=$(yq -r '.version' \
		charts/jenkins-lts-custom/Chart.yaml) &&
	ourrelver=$(git tag --list 'v*' | cut -c '2-' | sort -r --version-sort | head -1) &&
	true || return 1

	echo "::notice::Found jenkins chart $ouractver (released=$ourrelver) based on $helmactver locally, $helmver in Internet at $helmurl"

	return 0
}

##### updateHelm #############################################################
function updateHelm {
	# Update to latest Helm Chart, applying our patches on top

	if [ "$helmver" == "$helmactver" ] ; then
		echo "::notice::Not updating helm chart"
		return 0
	elif [ -d charts/jenkins-lts-custom ] ; then
		rm -rf charts/jenkins-lts-custom
		# do NOT check RC here!
	fi

	mkdir -p charts &&
	curl -L "$helmurl" 2>/dev/null | tar xz -C charts &&
	mv charts/jenkins charts/jenkins-lts-custom &&

	patchHelm &&

	git add charts/jenkins-lts-custom Dockerfile &&
	git commit -m "Bump to Jenkins Helm chart $helmver" &&
	true || return 1

	echo "::notice::Updated to jenkins chart $helmver based on image $origimage"

	return 0
}

##### updatePluginVersions ###################################################
function updatePluginVersions {
	# name: Generate Plugins Versions List plugins.txt from plugins-request.txt
	set -eo pipefail &&
	IMG=$(sed -n "s|FROM \(.*\)|\1|p" <Dockerfile) &&

	docker run \
		-v $(pwd)/plugins-request.txt:/plugins-request.txt \
		"$IMG" \
		jenkins-plugin-cli --no-download --list -f /plugins-request.txt \
	| sed -e '1,/Resulting plugin list:/d' -e '$d' -e 's/ /:/' \
		>plugins.txt &&
	true || exit 1

	if [[ $(git diff --stat) != '' ]] ; then
		git add plugins.txt &&
		git commit -m "Update Plugins" &&
		echo "::notice::Updated Plugins"
	else
		echo "::notice::No plugins to update"
	fi

	return 0
}

##### publish ################################################################
function publish {
	# Prepare Release 
	# @TODO to be implemented
		# ??? how to identify if to increase version or not???
		  # read version from Chart.yaml.
		  # if tag with that name does NOT exist
		  #   --> use tag as is
		  # else
		  #   --> increase tag
		# update version in chart (Chart.yaml and values.yaml)
		# tag version
		#
		# after push make sure to trigger the tag / release action
		# that should build the image, push it and push the chart

	if [[ $(git diff ${{ github.sha }} --stat) != '' ]] ; then
		echo "would execute git push"
		echo "::notice::Pushed updates to github repo"
	else
		echo "::notice::No updates to push"
	fi

	# Check if Build necessary
	if \
		[ "\${{ steps.diff-plugins.outputs.changed }}" != 'true' ] &&
		[ "\${{ steps.getImageNameTags.outputs.changed }}" != 'true' ] &&
		[ "\${{ github.event_name }}" != "push" ]
	then
		echo "nothing changed -> skip build"
		echo "::set-output name=build::false"
	elif [ "\${{ github.ref }}" == 'refs/heads/main' ] ; then
		echo "Building on main branch -> push with version+date"
		VERTAG="r"
		VERTAG+="$(git rev-list --count HEAD)"
		VERTAG+="."
		VERTAG+="$(git rev-parse --short HEAD)"
		echo "::set-output name=build::true"
		echo "::set-output name=tags::$VERTAG-$(date '+%Y%m%d%H%M')"
		echo "::set-output name=latest::true"
	elif [ "${GITHUB_REF#refs/heads/}" != "$GITHUB_REF" ] ; then
		echo "Building on non-main branch -> push with branchname"
		VERTAG="${GITHUB_REF#refs/heads/}"
		echo "::set-output name=build::true"
		echo "::set-output name=tags::$VERTAG"
		echo "::set-output name=latest::false"
	else
		echo "not building on a branch -> dont push"
		echo "::set-output name=build::true"
		echo "::set-output name=tags::"
		echo "::set-output name=latest::false"
	fi

	return 0
}

##### Main ###################################################################
rc=0

pushd $(dirname ${BASH_SOURCE:=$0})/../.. >/dev/null &&
# setup build machine by installing yq
# important to install from pip3, since preinstalled
# is another implementation of yq that is incompatible.
findLatestHelm &&
updateHelm &&
updatePluginVersions &&
publish &&

true || rc=1

popd >/dev/null

exit $rc
