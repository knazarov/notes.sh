#!/bin/bash

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
export BASE_DIR
cd "$BASE_DIR"

RESULT=0

testcase() {
	TMP=$(mktemp -d)
	cd "$TMP"
	NOTES_SH_BASEDIR="$(pwd)/notes"
	export NOTES_SH_BASEDIR

	(set -e && eval "$@")
	RES="$?"

	if [[ "$RES" == "0" ]]; then
		echo "$*: pass"
	else
		echo "$*: fail"
		RESULT=1
	fi
	cd "$BASE_DIR"
	rm -rf "$TMP"
}

assert() {
	if "$@"; then
		return 0
	else
		echo "Assert: 
	fi
}

new_note_from_stdin() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: This is a header

		# This is a body
	EOF

	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"

	test 1 = 2
}

testcase new_note_from_stdin


if [[ "$RESULT" == "0" ]]; then
	echo "All tests passed."
else
	echo "Some tests failed."
	exit 1
fi
