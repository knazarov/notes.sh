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

TESTNAME="$1"
RESULT=0

testcase() {
	if [ ! -z "$TESTNAME" ] && [[ "$TESTNAME" != "$1" ]]; then
		return
	fi
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

list_notes() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		# This is a body
	EOF
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header2

		# This is a body
	EOF

	OUTPUT="$("$BASE_DIR"/notes.sh -l)"

	assert 'echo "$OUTPUT" | grep -o header1' 'header1'
	assert 'echo "$OUTPUT" | grep -o header2' 'header2'
}

export_note() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		# This is a body
	EOF
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	mkdir out
	"$BASE_DIR/notes.sh" -E "$NOTE_ID" out

	assert 'cat out/note.md | grep Subject' "Subject: header1"
}

export_note_stdout() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		# This is a body
	EOF
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	MD="$("$BASE_DIR/notes.sh" -E "$NOTE_ID")"

	assert 'echo "$MD" | grep Subject' "Subject: header1"
}

edit_note() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		line1
	EOF
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	cat > "$(pwd)/editor.sh" <<- EOF
		#!/bin/bash
		FILENAME="\$1"
		echo "line2" >> "\$FILENAME"
	EOF
	chmod a+x "$(pwd)/editor.sh"
	export EDITOR="$(pwd)/editor.sh"

	"$BASE_DIR/notes.sh" -e "$NOTE_ID"

	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	assert 'echo "$OUTPUT" | grep -o line1' "line1"
	assert 'echo "$OUTPUT" | grep -o line2' "line2"
}

edit_note_add_file() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		line1
	EOF
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	cat > "$(pwd)/editor.sh" <<- EOF
		#!/bin/bash
		FILENAME="\$1"
		echo "newfile" > "\$FILENAME.txt"
	EOF
	chmod a+x "$(pwd)/editor.sh"
	export EDITOR="$(pwd)/editor.sh"

	"$BASE_DIR/notes.sh" -e "$NOTE_ID"

	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	assert 'echo "$OUTPUT" | grep -o line1' "line1"
	assert 'echo "$OUTPUT" | grep -o newfile' "newfile"
}

edit_note_no_modifications() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		line1
	EOF
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"
	NOTE_FILE="$(ls "$(pwd)/notes/cur"/*)"

	cat > "$(pwd)/editor.sh" <<- EOF
		#!/bin/bash
	EOF
	chmod a+x "$(pwd)/editor.sh"
	export EDITOR="$(pwd)/editor.sh"

	"$BASE_DIR/notes.sh" -e "$NOTE_ID"
	assert 'ls "$(pwd)/notes/cur"/*' "$NOTE_FILE"
}
resume_editing() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		myline1
	EOF
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	cat > "$(pwd)/editor.sh" <<- EOF
		#!/bin/bash
		FILENAME="\$1"
		echo "myline2" >> "\$FILENAME"
		exit 1
	EOF
	chmod a+x "$(pwd)/editor.sh"
	export EDITOR="$(pwd)/editor.sh"

	"$BASE_DIR/notes.sh" -e "$NOTE_ID" 2>/dev/null || true

	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	assert 'echo "$OUTPUT" | grep myline | wc -l | tr -d " "' "1"

	cat > "$(pwd)/editor.sh" <<- EOF
		#!/bin/bash
		FILENAME="\$1"
		echo "myline3" >> "\$FILENAME"
	EOF
	chmod a+x "$(pwd)/editor.sh"
	export EDITOR="$(pwd)/editor.sh"

	echo "y" | "$BASE_DIR/notes.sh" -e "$NOTE_ID"


	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	assert 'echo "$OUTPUT" | grep -o myline1' "myline1"
	assert 'echo "$OUTPUT" | grep -o myline2' "myline2"
	assert 'echo "$OUTPUT" | grep -o myline3' "myline3"
}

pack_multipart() {
	mkdir "$TMP/inpdir"
	cat > "$TMP/inpdir/note.md" <<- EOF
		Subject: This is a header

		This is a body
	EOF

	cat > "$TMP/inpdir/file.txt" <<- EOF
		This is a text attachment
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/inpdir"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	
	assert 'echo "$OUTPUT" | grep Subject' "Subject: This is a header"
	assert 'echo "$OUTPUT" | grep -o "text attachment"' "text attachment"
	BOUNDARY="$(cat "$(pwd)/notes/cur"/* | grep boundary= | cut -d '=' -f 2 | tr -d '\"')"
	#echo "boundary: $BOUNDARY"

	OUTPUT="$(echo "$OUTPUT" | sed "s/$BOUNDARY/boundary/g")"
	OUTPUT="$(echo "$OUTPUT" | grep -v "Date" | grep -v "X-Note-Id")"
	
	read -d '' -r EXPECTED <<- EOF || true
		MIME-Version: 1.0
		Content-Type: multipart/mixed; boundary="boundary"
		Subject: This is a header
		
		--boundary
		Content-Type: text/plain; charset=utf-8
		Content-Disposition: inline
		
		This is a body
		--boundary
		Content-Disposition: attachment; filename="file.txt"
		Content-Type: text/plain
		
		This is a text attachment
		--boundary--
	EOF

	assert 'echo "$OUTPUT"' "$EXPECTED"
}

pack_multipart_binary() {
	mkdir "$TMP/inpdir"
	cat > "$TMP/inpdir/note.md" <<- EOF
		Subject: This is a header

		This is a body
	EOF

	echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 --decode > "$TMP/inpdir/file.png"

	"$BASE_DIR/notes.sh" -n "$TMP/inpdir"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	
	assert 'echo "$OUTPUT" | grep Subject' "Subject: This is a header"

	BOUNDARY="$(cat "$(pwd)/notes/cur"/* | grep boundary= | cut -d '=' -f 2 | tr -d '\"')"
	#echo "boundary: $BOUNDARY"

	OUTPUT="$(echo "$OUTPUT" | sed "s/$BOUNDARY/boundary/g")"
	OUTPUT="$(echo "$OUTPUT" | grep -v "Date" | grep -v "X-Note-Id")"
	
	read -d '' -r EXPECTED <<- EOF || true
		MIME-Version: 1.0
		Content-Type: multipart/mixed; boundary="boundary"
		Subject: This is a header
		
		--boundary
		Content-Type: text/plain; charset=utf-8
		Content-Disposition: inline
		
		This is a body
		--boundary
		Content-Disposition: attachment; filename="file.png"
		Content-Type: image/png
		Content-Transfer-Encoding: base64

		iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6
		kgAAAABJRU5ErkJggg==
		--boundary--
	EOF

	assert 'echo "$OUTPUT"' "$EXPECTED"
}

existing_headers() {
	mkdir "$TMP/inpdir"
	NOTE_ID="6e50650a-88d1-49a3-92eb-0ec329e6f6f8"
	DATE="2021-05-29T18:47:34Z"

	cat > "$TMP/inpdir/note.md" <<- EOF
		X-Note-Id: $NOTE_ID
		X-Date: $DATE
		X-Custom: value
		Subject: This is a subject

		# This is a body
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/inpdir"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"
	
	assert 'echo "$OUTPUT" | grep Subject' "Subject: This is a subject"

	assert 'echo "$OUTPUT" | grep X-Note-Id' "X-Note-Id: $NOTE_ID"
	assert 'echo "$OUTPUT" | grep X-Date' "X-Date: $DATE"
	assert 'echo "$OUTPUT" | grep X-Custom' "X-Custom: value"
}

no_headers() {
	cat > "$TMP/input.md" <<- EOF
		This is a body
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/input.md"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"

	assert 'echo "$OUTPUT" | grep Subject' "Subject: "
	assert 'echo "$OUTPUT" | grep "This is a body"' "This is a body"
}

no_headers_dir() {
	mkdir "$TMP/inpdir"

	cat > "$TMP/inpdir/note.md" <<- EOF
		This is a body
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/inpdir"
	OUTPUT="$(cat "$(pwd)/notes/cur"/*)"

	assert 'echo "$OUTPUT" | grep Subject' "Subject: "
	assert 'echo "$OUTPUT" | grep "This is a body"' "This is a body"
}

import_export() {
	mkdir "$TMP/inpdir"
	NOTE_ID="6e50650a-88d1-49a3-92eb-0ec329e6f6f8"
	DATE="2021-05-29T18:47:34Z"

	cat > "$TMP/inpdir/note.md" <<- EOF
		X-Date: $DATE
		X-Note-Id: $NOTE_ID
		Subject: This is a subject

		This is a body
	EOF

	cat > "$TMP/inpdir/file.txt" <<- EOF
		This is a text attachment
	EOF

	"$BASE_DIR/notes.sh" -n "$TMP/inpdir"

	mkdir "$TMP/outpdir"

	"$BASE_DIR/notes.sh" -E $NOTE_ID "$TMP/outpdir"

	assert 'cat "$TMP/outpdir/note.md"' "$(cat "$TMP/inpdir/note.md")"
	assert 'cat "$TMP/outpdir/file.txt"' "$(cat "$TMP/inpdir/file.txt")"
}

new_note_overwrite_without_modifications() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1
		X-Date: 2021-05-30T18:25:38Z

		line1
	EOF

	NOTE_FILE="$(ls "$(pwd)/notes/cur"/*)"
	mv "$NOTE_FILE" "$NOTE_FILE.keep"
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	mkdir "$TMP/outdir"
	"$BASE_DIR/notes.sh" -E "$NOTE_ID" "$TMP/outdir"

	"$BASE_DIR/notes.sh" -n "$TMP/outdir"

	assert 'ls "$(pwd)/notes/cur"/*' "$NOTE_FILE.keep"
}

new_note_overwrite_with_modifications() {
	"$BASE_DIR/notes.sh" -n <<- EOF
		Subject: header1

		line1
	EOF

	NOTE_FILE="$(ls "$(pwd)/notes/cur"/*)"
	NOTE_ID="$(cat "$(pwd)/notes/cur"/* | grep X-Note-Id | cut -d ' ' -f 2)"

	mkdir "$TMP/outdir"
	"$BASE_DIR/notes.sh" -E "$NOTE_ID" "$TMP/outdir"

	echo "line2" >> "$TMP/outdir/note.md"

	"$BASE_DIR/notes.sh" -n "$TMP/outdir"

	assert 'cat "$(pwd)/notes/cur"/* | grep line2' "line2"
}

testcase new_note_from_stdin
testcase new_note_from_file
testcase new_note_from_dir
testcase list_notes
testcase export_note
testcase export_note_stdout
testcase edit_note
testcase edit_note_add_file
testcase edit_note_no_modifications
testcase resume_editing
testcase pack_multipart
testcase pack_multipart_binary
testcase existing_headers
testcase no_headers
testcase no_headers_dir
testcase import_export
testcase new_note_overwrite_without_modifications
testcase new_note_overwrite_with_modifications

if [[ "$RESULT" == "0" ]]; then
	echo "All tests passed."
else
	echo "Some tests failed."
	exit 1
fi
