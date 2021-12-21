#!/bin/bash
#
# (C) 2021 Stefan Schallenberg
#

function test_emptyhelm {
    test_exec_simple "rm -rf charts/jenkins-lts-custom" "0" &&
        test_expect_file_missing "charts/jenkins-lts-custom" &&
        true || return 1

    # autoupdate without any helm chart should fail
    test_exec_simple ".github/workflows/autoupdate.sh" "1" &&
        test_expect_file_missing "charts/jenkins-lts-custom" &&

    return 0
}

function test_bootstrap {
    # autoupdate with just bootstrap helm chart should work
    export GITHUB_REF="refs/heads/$(git branch --show-current)"

    test_exec_simple "mkdir -p charts/jenkins-lts-custom"
    test_exec_simple "cp -a $BASEDIR/jenkins-lts-custom.bootstrap/* charts/jenkins-lts-custom"
    test_exec_simple ".github/workflows/autoupdate.sh" &&
        test_lastoutput_contains "::set-output name=newVersion::0.0.2-chartsubmodule-localtest+$(date "+%Y%m%d")"
    local gittag
    gittag=$(git tag -l v0.0.2-chartsubmodule-localtest+$(date "+%Y%m%d")'*')
    test_expect_value "$?" "0"
    test_expect_value "${#gittag}" "46"
    test_exec_simple "git tag -d $gittag"
    export GITHUB_REF=

    return 0
}

##### Test Build #############################################################
function test_build {

	# Compile / Build docker
	test_exec_simple \
		"docker build -t nafets227/jenkins-lts-custom:test $BASEDIR/.." \
		0

	[ $TESTRC -eq 0 ] || return 1

	return 0
}
