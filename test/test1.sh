#!/bin/bash
#
# (C) 2021 Stefan Schallenberg
#

function test_1 {
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
