#!/bin/bash
#
# Distributed under the terms of the BSD License
#
# Copyright (c) 2021, Konstantin Nazarov <mail@knazarov.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
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
	# assert <command> <expected stdout> [stdin]

	command="$1"
	expected="$(echo -ne "${2:-}")"
	result="$(eval 2>/dev/null $1 <<< ${3:-})" || true
	
	if [[ "$result" == "$expected" ]]; then
        return
    fi
	result="$(sed -e :a -e '$!N;s/\n/\\n/;ta' <<< "$result")"

	echo "Expected '$command' == '$expected'. Got: '$result'"
	exit 1
}

new_note_from_stdin() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: This is a header

		# This is a body
	EOF

	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"

	assert 'echo "$OUTPUT" | grep Content-Type:' "Content-Type: text/plain; charset=utf-8"
	assert 'echo "$OUTPUT" | grep MIME-Version:' "MIME-Version: 1.0"
	assert 'echo "$OUTPUT" | grep Content-Disposition:' "Content-Disposition: inline"

	assert 'echo "$OUTPUT" | grep Subject' "Subject: This is a header"

}

new_note_from_file() {
	cat > "$TMP/input.md" <<- EOF
		Subject: This is a header

		# This is a body
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/input.md"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	
	assert 'echo "$OUTPUT" | grep Subject' "Subject: This is a header"
}

new_note_from_dir() {
	mkdir "$TMP/inpdir"
	cat > "$TMP/inpdir/note.md" <<- EOF
		Subject: This is a header

		# This is a body
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/inpdir"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	
	assert 'echo "$OUTPUT" | grep Subject' "Subject: This is a header"
}

testcase new_note_from_stdin
testcase new_note_from_file
testcase new_note_from_dir

if [[ "$RESULT" == "0" ]]; then
	echo "All tests passed."
else
	echo "Some tests failed."
	exit 1
fi
