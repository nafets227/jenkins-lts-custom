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

	local sedregex &&
	sedregex="s#" &&
	sedregex+="image: {{ .Values.controller.image }}:{{ .Chart.AppVersion }}-{{ .Values.controller.tagLabel }}" &&
	sedregex+="#" &&
	sedregex+="image: \"{{ .Values.controller.image }}:{{- include \"controller.tag\" . -}}\"" &&
	sedregex+="#" &&
	sed -i -e "$sedregex" $DIR/templates/tests/jenkins-test.yaml &&

	yq -Y -i ". 
		| .controller.image |= \"ghcr.io/nafets227/jenkins-lts-custom\"
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

##### calcNewVersion ##########################################################
function calcNewVersion {
	if git describe --tags --exact-match --match 'v*' >/dev/null 2>&1 ; then
		printf "::notice::No updates. Staying on %s\n" \
			"$(git describe --tags --exact-match --match 'v*' 2>/dev/null)"
		newVersion=""
		return 0
	elif [ "$GITHUB_REF" == "" ] ; then
		echo "::notice::Not publishing in test Mode (GITHUB_REF unset)"
		newVersion=""
		return 0
	elif [ "${GITHUB_REF#refs/heads/}" == "$GITHUB_REF" ] ; then
		echo "::notice::Not publishing since $GITHUB_REF is no branch"
		newVersion=""
		return 0
	fi

	local helmver helmversem helmver_main helmver_suffix gittag branchname

	# ouractver has been previously set to the version tag in 
	# charts/jenkins-lts-custom/Chart.yaml
	helmver="$ouractver" &&
	helmversem=( ${helmver//./ } ) &&
	helmver_main=${helmver##-*} &&
	helmver_main=${helmver_main##+*} &&
	helmver_suffix=${helmver:${#helmver_main}} &&

	gittag=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null | cut -c "2-" ) &&

	branchname="${GITHUB_REF##refs/heads/}" &&
	true || return 1

	if	[ -z "$helmver" ] ||
		[ -z "$helmver_main" ] ||
		[ -z "$gittag" ] ||
		[ -z "$branchname" ]
	then
		echo -n "Internal error in calcNewVersion."
		echo -n " helmver=$helmver helmver_main=$helmver_main"
		echo    " gittag=$gittag branchname=$branchname"
		return 1
	fi

	if	 [ "$GITHUB_REF" != 'refs/heads/main' ] &&
	     [ "$helmver_suffix" != '' ]
	then
		#if !main and helmver contains pre-release/build-info
		#	use major.minor.patch from helmtag and add suffix -<branchname>.<timestamp>
		newVersion="${helmversem[0]}.${helmversem[1]}.${helmversem[2]}"
		newVersion+="-${branchname//[!0-9A-Za-z-]/-}.$(date '+%Y%m%d%H%M%S')"
		return 0
	elif [ "$GITHUB_REF" != 'refs/heads/main' ] &&
	     [ "$helmver_suffix" == '' ]
	then
		#if !main and helmver does not contain pre-release/buildinfo
		#	use major,minor from helmver
		#	use patch from helmver, increase it
		#	add suffix -<branchname>.<timestamp>
		newVersion="${helmversem[0]}.${helmversem[1]}.$((${helmversem[2]} + 1))"
		newVersion+="-${branchname//[!0-9A-Za-z-]/-}.$(date '+%Y%m%d%H%M%S')"
		return 0
	elif [ "$GITHUB_REF" == 'refs/heads/main' ] &&
	     [ "$helmver_suffix" != '' ]
	then
		#if main and semver pre-release (-...) and/or semver build-info (+...)
		#	cowardly stop.
		echo -n "::notice::Cowardly refusing to define and publish a version"
		echo    " based on helmver=$helmver and gittag=$gittag on main branch"
		newVersion=""
		return 0
	elif [ "$GITHUB_REF" == 'refs/heads/main' ] &&
	     [ "$helmver_suffix" == '' ] &&
		 [ "$helmver" == "$gittag" ]
	then
		#if main, no pre-release/build-info, gittag==helmver
		#	increase patch
		newVersion="${helmversem[0]}.${helmversem[1]}.$((${helmversem[2]} + 1))"
		return 0
	elif [ "$GITHUB_REF" == 'refs/heads/main' ] &&
	     [ "$helmver_suffix" == '' ] &&
		 [ "$helmver" < "$gittag" ]
	then
		#if main, no pre-release/build-info, gittag>helmver
		#	cowardly stop (we might be overwriting something)
		echo -n "::notice::Cowardly refusing to define and publish a version"
		echo    " based on helmver=$helmver and gittag=$gittag on main branch"
		newVersion=""
		return 0
	elif [ "$GITHUB_REF" == 'refs/heads/main' ] &&
	     [ "$helmver_suffix" == '' ] &&
		 [ "$helmver" > "$gittag" ]
	then
		#if main, no pre-release/build-info, gittag<helmver
		#	use helmtag (probably it has been manually set to increase major or minor)
		newVersion="$helmtag"
		return 0
	fi 

	echo -n "::notice::reaching uncovered condition when defining newVersion"
	echo    "helmver=$helmver gittag=$gittag branch=$branchname"
	return 1 # should never end here
}

##### publish ################################################################
function publish {
	# input: variable newVersion contains the version (without leading v)
	local newVersion="$1"
	if [ -z "$newVersion" ] ; then
		printf "Error: version to publish not set.\n"
		return 1
	fi

	local annImages
	annImages=$(
		yq -r ".annotations.\"artifacthub.io/images\"" charts/jenkins-lts-custom/Chart.yaml
		) &&
	annImages=$(yq -Y ".
		| ( .[]
			| select(.name == \"jenkins\")
			| .image )
		|=\"ghcr.io/nafets227/jenkins-lts-custom:$newVersion\"
		" - <<<"$annImages"
		) &&
	annImages=$(jq -aRs <<<"$annImages") &&
	yq -Y -i ".
		| .version |= \"$newVersion\"
		| .annotations.\"artifacthub.io/images\" |= $annImages
		" \
		charts/jenkins-lts-custom/Chart.yaml &&

	yq -Y -i ". 
		| .controller.tag |= \"$newVersion\"
		" \
		charts/jenkins-lts-custom/values.yaml &&

	git add \
		charts/jenkins-lts-custom/Chart.yaml \
		charts/jenkins-lts-custom/values.yaml \
		&&
	git commit -m "Prepare release $newVersion" &&
	# git tag "v$newVersion" &&
	# git push origin refs/tags/v$newVersion "$GITHUB_REF" &&
	git push origin "$GITHUB_REF" &&
	true || return 1

	echo "::notice::Pushed updates to github repo"

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
calcNewVersion && # sets newVersion!!!
true || rc=1

if [ "$rc" == "0" ] && [ ! -z "$newVersion" ] ; then
	publish "$newVersion" || rc=1
	echo "::set-output name=newVersion::$newVersion"
fi

popd >/dev/null

exit $rc
