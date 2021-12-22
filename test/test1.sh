#!/bin/bash
#
# (C) 2021 Stefan Schallenberg
#

function test_emptyhelm {
    git checkout -q -b "$FUNCNAME" &&
    test_exec_simple "rm -rf charts/jenkins-lts-custom" "0" &&
        test_expect_file_missing "charts/jenkins-lts-custom" &&
        true || return 1

    # autoupdate without any helm chart should fail
    test_exec_simple ".github/workflows/autoupdate.sh" "1" &&
        test_expect_file_missing "charts/jenkins-lts-custom" &&
        test_expect_value "$(git status --porcelain)" \
            " D charts/jenkins-lts-custom/Chart.yaml" &&

    return 0
}

function test_nopluginsreq {
    git checkout -q -b "$FUNCNAME" &&
    test_exec_simple "rm -rf plugins-request.txt" "0" &&
        test_expect_file_missing "plugins-request.txt" &&
        test_expect_file_missing "plugins.txt" &&
        true || return 1

    # autoupdate without plugins-request.txt should fail
    test_exec_simple ".github/workflows/autoupdate.sh" "1" &&
        test_expect_file_missing "plugins-request.txt" &&
        test_expect_file_missing "plugins.txt" &&

    return 0
}

function test_nodockerfile {
    git checkout -q -b "$FUNCNAME" &&
    :
}

function test_bootstrap {
    # autoupdate with just bootstrap helm chart should work
    git checkout -q -b "$FUNCNAME" &&
    export GITHUB_REF="refs/heads/$(git branch --show-current)" &&
    test_exec_simple ".github/workflows/autoupdate.sh" &&
        test_lastoutput_contains "::set-output name=newVersion::0.0.2-test-bootstrap.$(date "+%Y%m%d")" &&
        test_expect_files "gittestrepo" "6" &&
        test_expect_value "$(git status --porcelain)" "" &&
    test_exec_simple "git log testmain..HEAD --oneline" &&
        test_lastoutput_contains "Prepare release 0.0.2-test-bootstrap" &&
        test_lastoutput_contains "Update Plugins" &&
        test_lastoutput_contains "Bump to Jenkins Helm chart" &&

    export GITHUB_REF= &&

    true || return 1

    return 0
}

function test_mainbranch {
    # autoupdate with just bootstrap helm chart should work
    git checkout -q -b "main" &&
    export GITHUB_REF="refs/heads/$(git branch --show-current)" &&
    test_exec_simple "bash -c 'set -x ; . .github/workflows/autoupdate.sh'" &&
        test_lastoutput_contains "::set-output name=newVersion::0.0.1$" &&
        test_expect_files "gittestrepo" "6" &&
        test_expect_value "$(git status --porcelain)" "" &&
    test_exec_simple "git log testmain..HEAD --oneline" &&
        test_lastoutput_contains "Prepare release 0.0.1$" &&
        test_lastoutput_contains "Update Plugins" &&
        test_lastoutput_contains "Bump to Jenkins Helm chart" &&

    export GITHUB_REF= &&

    true || return 1

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
