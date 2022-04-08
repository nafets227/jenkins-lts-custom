#!/bin/bash
#
# generate helm chart under nafets227/jenkins-lts-custom name
# starting from jenkinsci/helm-charts that are in submodule with same name
#

##### util_semver_islt #######################################################
function util_semver_islt {
	local min
	min=$( printf "%s\n%s" "$1" "$2" \
		| sort --version-sort \
		| head -1
		)
	if [ "$min" == "$1" ] ; then
		return 0 #true
	elif [ "$min" == "$2" ] ; then
		return 1 #false
	else
		printf "ERROR\n"
		return 255
	fi

	return 99 # should never be reached
}

##### patchHelm ##############################################################
function patchHelm {
	local DIR annimages helmver orighelmver origannimages origimage sedregex

	helmver="$1"
	if [ -z "$helmver" ] ; then
		printf "Internal Error: Parm1 cannot be null\n"
		return 1
	fi

	DIR=charts/jenkins-lts-custom

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
	origannimages=$(
		yq -r ".annotations.\"artifacthub.io/images\"" $DIR/Chart.yaml
		) &&
	annimages=$(yq -Y ".
		| ( .[]
			| select(.name == \"jenkins\")
			| .image )
		|=\"ghcr.io/nafets227/jenkins-lts-custom:$helmver\"
		" - <<<"$origAnnImages"
		) &&
	annimages=$(jq -aRs <<<"$annImages") &&

	yq -Y -i ".
		| .name |= \"jenkins-lts-custom\"
		| .description |= \"Jenkins with custom plugins autoupdated\"
		| .version |= \"$helmver\"
		| .home |= \"https://github.com/nafets227/jenkins-lts-custom\"
		| .sources += [ \"https://github.com/nafets227/jenkins-lts-custom\" ]
		| .maintainers |= [{\"name\": \"nafets227\", \"email\": \"nafets227@users.noreply.github.com\"}]
		| .annotations.\"artifacthub.io/links\" |= \"https://github.com/nafets227/jenkinsci-lts-custom/helm-charts/tree/main/charts/jenkins\"
		| .annotations.\"artifacthub.io/images\" |= $annimages
		| .annotations.\"nafets227.github.com/basechart\" |= \"$orighelmver\"
		| .annotations.\"nafets227.github.com/baseimage\" |= \"$origimage\"
		" \
		$DIR/Chart.yaml &&

	sedregex="s#" &&
	sedregex+="image: {{ .Values.controller.image }}:{{ .Chart.AppVersion }}-{{ .Values.controller.tagLabel }}" &&
	sedregex+="#" &&
	sedregex+="image: \"{{ .Values.controller.image }}:{{- include \"controller.tag\" . -}}\"" &&
	sedregex+="#" &&
	sed -e "$sedregex" \
		<$DIR/templates/tests/jenkins-test.yaml \
		>$DIR/templates/tests/jenkins-test.yaml.new &&
	mv \
		$DIR/templates/tests/jenkins-test.yaml.new \
		$DIR/templates/tests/jenkins-test.yaml &&

	yq -Y -i ".
		| .controller.image |= \"ghcr.io/nafets227/jenkins-lts-custom\"
		| .controller.tag |= \"$helmver\"
		| del(.controller.tagLabel)
		| .controller.installPlugins |= false
		" \
		$DIR/values.yaml &&

	mkdir -p $DIR/ci  &&
	cat >$DIR/ci/default-values.yaml <<-EOF &&
		# use default values
		controller:
		  adminPassword: "admin"
		EOF

	cat >$DIR/ci/nopluginload-values.yaml <<-EOF &&
		# disable access to plugin store
		# we simply reroute to localhost
		hostAliases:
		  - ip: 127.0.0.1
		    hostnames:
		      - updates.jenkins.io
		controller:
		  adminPassword: "admin"
		EOF

	sed '$d' \
		<$DIR/templates/tests/test-config.yaml \
		>$DIR/templates/tests/test-config.yaml.new &&
	mv \
		$DIR/templates/tests/test-config.yaml.new \
		$DIR/templates/tests/test-config.yaml &&

	cat >>$DIR/templates/tests/test-config.yaml <<-EOF &&
		    @test "Download jq" {
		      curl -L https://github.com/stedolan/jq/releases/latest/download/jq-linux64 >/tools/jq
		      chmod +x /tools/jq
		    }
		    @test "download list of plugins" {
		      curl --retry 48 --retry-delay 10 --fail -u admin:admin {{ template "jenkins.fullname" . }}:{{ .Values.controller.servicePort }}{{ default "" .Values.controller.jenkinsUriPrefix }}/pluginManager/api/json?depth=1 | /tools/jq -r '.plugins[] | .shortName + ":" + .version' >/tools/plugins.as-is
		    }
		    @test "Testing all Jenkins plugins are included in image" {
		      diff <(sort /usr/share/jenkins/ref/plugins.txt) <(sort </tools/plugins.as-is)
		    }
		{{- end }}
		EOF

	sed -e "s|FROM .*|FROM $origimage|" <Dockerfile >Dockerfile.new &&
	mv Dockerfile.new Dockerfile &&

	rm $DIR/CHANGELOG.md $DIR/README.md &&

	true || return 1

	return 0
}

##### findLatestHelm #########################################################
function findLatestHelm {
	# Analyse Jenkins Helm chart versions (actual and latest from internet)
	# get latest version from helm chart repository
	local helmchartjson
	helmchartjson=$(curl https://charts.jenkins.io/index.yaml 2>/dev/null |
		yq '.entries.jenkins | max_by(.version | split(".") | map(tonumber))'
		) &&
	helmver=$(jq -r '.version' - <<<$helmchartjson) &&
	helmurl=$(jq -r '.urls[0]' - <<<$helmchartjson) &&
	# as described in https://github.com/helm/helm/issues/7314 only first value of urls

	helmactver=$(yq -r '.annotations."nafets227.github.com/basechart"' \
		charts/jenkins-lts-custom/Chart.yaml) &&
	true || return 1

	echo "::notice::Found jenkins chart based on $helmactver locally, $helmver in Internet at $helmurl"

	return 0
}

##### updateHelm #############################################################
function updateHelm {
	# Update to latest Helm Chart, applying our patches on top

	local msgCommit image

	findLatestHelm || return 1

	if [ "$1" == "--force" ]; then
		msgCommit="Recreated helm chart jenkins:$helmver"
	elif [ "$helmver" == "$helmactver" ] ; then
		echo "::notice::Not updating helm chart, already at jenkins:$helmver"
		return 0
	else
		msgCommit="Bump to helm chart jenkins:$helmver"
	fi

	curver="$(yq -r '.version' \
		charts/jenkins-lts-custom/Chart.yaml)" &&
	true || return 1

	if [ -d charts/jenkins-lts-custom ] ; then
		rm -rf charts/jenkins-lts-custom
		# do NOT check RC here!
	fi

	mkdir -p charts &&
	curl -L "$helmurl" 2>/dev/null | tar xz -C charts &&
	mv charts/jenkins charts/jenkins-lts-custom &&

	patchHelm "$curver" &&

	image=$(sed -n "s|FROM \(.*\)|\1|p" <Dockerfile) &&
	git add -A charts/jenkins-lts-custom Dockerfile &&
	true || return 1

	if ! git diff-index --quiet HEAD ; then
		# something has been modified -> commit it
		git commit -m "$msgCommit based on image $image" &&
		true || return 1
		fi

	echo "::notice::$msgCommit"

	return 0
}

##### updatePluginVersions ###################################################
function updatePluginVersions {
	# name: Generate Plugins Versions List plugins.txt from plugins-request.txt
	local image && 
	set -eo pipefail &&
	image=$(sed -n "s|FROM \(.*\)|\1|p" <Dockerfile) &&

	docker run \
		-v $(pwd)/plugins-request.txt:/plugins-request.txt \
		"$image" \
		jenkins-plugin-cli --no-download --list -f /plugins-request.txt \
	| sed -e '1,/Resulting plugin list:/d' -e '$d' -e 's/ /:/' \
		>plugins.txt &&
	true || exit 1

	if [[ $(git status --porcelain plugins.txt) != '' ]] ; then
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
	local gitbasecommit gitactcommit
	gitbasecommit="$1"
	gitactcommit="$(git rev-parse --verify HEAD)"

	if [ "$gitbasecommit" == "$gitactcommit" ] ; then
		echo "::notice::Not publishing without changes"
		newVersion=""
		return 0
	elif [ "$GITHUB_REF" == "" ] ; then
		echo "::notice::Not publishing in test Mode (GITHUB_REF unset)"
		newVersion=""
		return 1
	elif [ "${GITHUB_REF#refs/heads/}" == "$GITHUB_REF" ] ; then
		echo "::notice::Not publishing since $GITHUB_REF is no branch"
		newVersion=""
		return 1
	fi

	local curver curversem curvermain curversuffix branchname

	curver="$(yq -r '.version' \
		charts/jenkins-lts-custom/Chart.yaml)" &&
	curvermain=${curver%%-*} &&
	curvermain=${curvermain%%+*} &&
	curversuffix=${curver:${#curvermain}} &&
	curversem=( ${curvermain//./ } ) &&

	branchname="${GITHUB_REF##refs/heads/}" &&
	true || return 1

	if	[ -z "$curver" ] ||
		[ -z "$curvermain" ] ||
		[ -z "$branchname" ]
	then
		echo -n "Internal error in calcNewVersion."
		echo -n " curver=$curver curvermain=$curvermain"
		echo    " branchname=$branchname"
		return 1
	fi

	if	 [ "$GITHUB_REF" != 'refs/heads/main' ] &&
	     [ "$curversuffix" != '' ]
	then
		#if !main and curver contains pre-release/build-info
		#	use major.minor.patch from helmtag and add suffix -<branchname>.<timestamp>
		newVersion="${curversem[0]}.${curversem[1]}.${curversem[2]}"
		newVersion+="-${branchname//[!0-9A-Za-z-]/-}.$(date '+%Y%m%d%H%M%S')"
		return 0
	elif [ "$GITHUB_REF" != 'refs/heads/main' ] &&
	     [ "$curversuffix" == '' ]
	then
		#if !main and curver does not contain pre-release/buildinfo
		#	use major,minor from curver
		#	use patch from curver, increase it
		#	add suffix -<branchname>.<timestamp>
		newVersion="${curversem[0]}.${curversem[1]}.$((${curversem[2]} + 1))"
		newVersion+="-${branchname//[!0-9A-Za-z-]/-}.$(date '+%Y%m%d%H%M%S')"
		return 0
	elif [ "$GITHUB_REF" == 'refs/heads/main' ] &&
	     [ "$curversuffix" != '' ]
	then
		#if main and semver pre-release (-...) and/or semver build-info (+...)
		#	cowardly stop.
		echo -n "::notice::Cowardly refusing to define and publish a version"
		echo    " based on pre-release curver=$curver on main branch"
		newVersion=""
		return 1
	elif [ "$GITHUB_REF" == 'refs/heads/main' ] &&
	     [ "$curversuffix" == '' ]
	then
		#if main, no pre-release/build-info
		#	increase patch
		newVersion="${curversem[0]}.${curversem[1]}.$((${curversem[2]} + 1))"
		return 0
	fi

	echo -n "::notice::reaching uncovered condition when defining newVersion"
	echo    "curver=$curver branch=$branchname"
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
	true || return 1

	echo "::notice::Updated chart version to $newVersion"

	return 0
}

##### Main ###################################################################
rc=0

pushd $(dirname ${BASH_SOURCE:=$0})/../.. >/dev/null &&

if [ "$1" == "--force" ] ; then
	updParm="--force"
	updBase=""
else
	updParm=""
	updBase="$(git rev-parse --verify HEAD)" || exit 1
fi

updateHelm $updParm &&
updatePluginVersions &&
calcNewVersion "$updBase" && # sets newVersion!!!
true || rc=1

if [ "$rc" == "0" ] ; then
	if [ ! -z "$newVersion" ] ; then
		publish "$newVersion" || rc=1
	fi
	echo "::set-output name=newVersion::$newVersion"
fi

popd >/dev/null

exit $rc
