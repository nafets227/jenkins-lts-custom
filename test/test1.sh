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

function test_2 {
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
