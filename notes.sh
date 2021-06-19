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

set -e

DATE_FORMAT="%a, %d %b %Y %H:%M:%S %z"
PID=$$
BASEDIR=~/Maildir/personal/Notes
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/notes.sh"
EDITOR="${EDITOR:-vim}"

if [ -n "$NOTES_SH_BASEDIR" ]; then
	BASEDIR="$NOTES_SH_BASEDIR"
fi


if [ ! -d "$BASEDIR" ]; then
	mkdir -p "$BASEDIR"/{tmp,new,cur}
fi

die() {
	echo "$@" 1>&2;
	exit 1
}

uuid()
{
    local N B T

    for (( N=0; N < 16; ++N ))
    do
        B=$(( RANDOM%255 ))

        if (( N == 6 ))
        then
            printf '4%x' $(( B%15 ))
        elif (( N == 8 ))
        then
            local C='89ab'
            printf '%c%x' ${C:$(( RANDOM%${#C} )):1} $(( B%15 ))
        else
            printf '%02x' $B
        fi

        for T in 3 5 7 9
        do
            if (( T == N ))
            then
                printf '-'
                break
            fi
        done
    done

    echo
}

utc_timestamp() {
	date -u +"%Y-%m-%dT%H:%M:%SZ"
}

gen_boundary()
{
	for (( N=0; N < 32; ++N ))
	do
		B=$(( RANDOM%255 ))
		printf '%02x' $B
	done
	echo
}

yesno() {
	PROMPT="$1"
	DEFAULT="$2"

	if [[ "$DEFAULT" == "y" ]]; then
		read -p "$PROMPT [Y/n] " -r CHOICE
		if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
			echo "n"
		else
			echo "y"
		fi
	else
		read -p "$PROMPT [y/N] " -r CHOICE
		if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
			echo "y"
		else
			echo "n"
		fi
	fi
}

get_headers() {
	HEADERS_FILE="$1"
	
	FILTER="\
		{ \
		    if (\$0~/^$/) {exit} \
		    if (\$0!~/^[^ ]*: .*$/) {exit} \
		    print \$0 \
		} \
	"
	awk "$FILTER" "$HEADERS_FILE"
}

get_body() {
	BODY_FILE="$1"
	
	FILTER="\
		{ \
		    if (body==1) {\
				print \$0;
			}\
		    if (\$0~/^$/) {body=1} \
		    if (\$0!~/^[^ ]*: .*$/ && body != 1) {\
				body=1;
				print \$0;
			} \
		} \
	"
	awk "$FILTER" "$BODY_FILE" 
}
get_header() {
	FILE="$1"
	HEADER="$2"
	grep -m1 "^${HEADER}: " < "$FILE" | sed -n "s/^${HEADER}: \(.*\)$/\1/p"
}

find_file_by_id() {
	ID="$1"

	{ grep -l -r -m1 "^X-Note-Id: $ID$" "$BASEDIR" || true; } | sort| head -1
}

assert_find_file_by_id() {
	FILE="$(find_file_by_id "$1")"

	if [ ! -f "$FILE" ]; then
		die "Note with ID <$ID> not found"
	fi

	echo "$FILE"
}

find_files_by_id() {
	ID="$1"
	grep -l -r -m 1 "^X-Note-Id: $ID$" "$BASEDIR" || true
}

get_part() {
	FILE="$1"
	BOUNDARY="$2"
	NUM="$3"
	FILTER="\
		BEGIN { \
			rec=0; \
			body=0; \
		} \
		{ \
		    if (\$0==\"--$BOUNDARY\" || \$0==\"--$BOUNDARY--\") { \
				if (body == 0) { \
				    body=1; \
			    } \
			    rec=rec+1; \
			} \
		    else if (body == 1 && rec==$NUM) { \
				print \$0 \
			} \
	    }" 

	awk "$FILTER" "$FILE"
}

unpack_part() {
	FILE="$1"
	DIR="$2"
	MIME_TYPE=$(get_header "$FILE" Content-Type)
	DISPOSITION=$(get_header "$FILE" Content-Disposition)

	if [[ $DISPOSITION == *"attachment"* ]]; then
		ENCODING=$(get_header "$FILE" Content-Transfer-Encoding)
		FILENAME=$(echo "$DISPOSITION" | \
			sed -n 's/^.*filename="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
		FILTER="\
			{ \
			    if (body==1) {print \$0}\
			    if (\$0~/^$/) {body=1} \
			} \
		"
    
		if [[ $ENCODING == *"base64"* ]]; then
			awk "$FILTER" "$FILE" | base64 --decode >> "$DIR/$FILENAME"
		else
			awk "$FILTER" "$FILE" >> "$DIR/$FILENAME"
		fi
	elif [[ $MIME_TYPE == *"text/plain"* ]]; then
		FILTER="\
			{ \
			    if (body==1) {print \$0}\
			    if (\$0~/^$/) {body=1} \
			} \
		"
		awk "$FILTER" "$FILE" >> "$DIR/note.md"
	elif [[ $MIME_TYPE == *"multipart/mixed"* ]]; then
		BOUNDARY=$(echo "$MIME_TYPE" | sed -n 's/^.*boundary="\(.*\)"$/\1/p')
		i=1
		while true; do
		    TMP=$(mktemp --tmpdir="$DIR")
		    get_part "$FILE" "$BOUNDARY" "$i" > "$TMP"
			((i++))
			if [ ! -s "$TMP" ]; then
				rm "$TMP"
				break
			fi
			#cat "$TMP"
			(unpack_part "$TMP" "$DIR")
			rm "$TMP"
		done
	elif [[ $MIME_TYPE == *"multipart/related"* ]]; then
		echo "multipart/related not yet supported"
		exit 1
	fi
}



unpack_mime() {
	FILE="$1"
	DIR="$2"

	get_headers "$FILE" | grep -v "^Content-Type\|^Content-Disposition\|^Date\|^MIME-Version" >> "$DIR/note.md"
	echo "" >> "$DIR/note.md"

	TMP=$(mktemp --tmpdir="$DIR")
	cat "$FILE" > "$TMP"

	(unpack_part "$TMP" "$DIR")
	rm "$TMP"
}

pack_part() {
	PART_FILE="$1"
	CONTENT_TYPE="$(file -b --mime-type "$PART_FILE")"
	echo "Content-Disposition: attachment; filename=\"$(basename "$PART_FILE")\""

	if [[ "$CONTENT_TYPE" =~ "text/" ]]; then
		echo "Content-Type: text/plain"
		echo
		cat "$PART_FILE"
	else
		echo "Content-Type: $CONTENT_TYPE"
		echo "Content-Transfer-Encoding: base64"
		echo
		base64 < "$PART_FILE"
	fi
}

pack_mime() {
	DIR="$1"
	FILE="$2"
	FILE_COUNT="$(find "$DIR/" -type f | wc -l)"
	MIME_TIMESTAMP=$(LC_ALL="en_US.UTF-8" date "+$DATE_FORMAT")

	if [[ "$FILE_COUNT" == "1" ]]; then
		{
			echo "MIME-Version: 1.0"
			echo "Date: $MIME_TIMESTAMP"
			echo "Content-Type: text/plain; charset=utf-8"
			echo "Content-Disposition: inline"
			cat "$DIR/note.md"
		} >> "$FILE"
		return
	fi

	BOUNDARY="$(gen_boundary)"
	{
		echo "MIME-Version: 1.0"
		echo "Date: $MIME_TIMESTAMP"
		echo "Content-Type: multipart/mixed; boundary=\"$BOUNDARY\""
		get_headers "$DIR/note.md" 
		echo
		echo "--$BOUNDARY"
		echo "Content-Type: text/plain; charset=utf-8"
		echo "Content-Disposition: inline"
		echo
		get_body "$DIR/note.md"
	} >> "$FILE"


	find "$DIR/" -type f ! -name 'note.md' | while read -r FN
	do
		{
			echo "--$BOUNDARY"
			pack_part "$FN"
		} >> "$FILE"
	done	
	echo "--$BOUNDARY--" >> "$FILE"
}

input_note() {
	INP="$1"
	OUTP="$2"

	DIR="$(mktemp -d)"
	ENTRY_FILE="$DIR/note.md"
	MIME_TIMESTAMP=$(LC_ALL="en_US.UTF-8" date "+$DATE_FORMAT")
	UTC_TIMESTAMP=$(utc_timestamp)

	if [ -n "$INP" ] && [ ! -f "$INP" ] && [ ! -d "$INP" ]; then
		die "File or directory doesn't exist: $INP"
	fi

	if [ -f "$INP" ]; then
		{
			get_headers "$INP"
			echo "" 
			get_body "$INP"
		} >> "$DIR/note.md"
	elif [ -d "$INP" ]; then
		if [ ! -f "$INP/note.md" ]; then
			die "File doesn't exist: $INP/note.md"
		fi
		cp -n "$INP"/* "$DIR/" || true
	elif [ -t 0 ]; then
		cat > "$ENTRY_FILE" <<- EOF
			X-Date: $UTC_TIMESTAMP
			X-Note-Id: $(uuid)
			Subject: 
		EOF
		OLD_DIR="$(pwd)"
		cd "$DIR"
		"$EDITOR" "$ENTRY_FILE"
		cd "$OLD_DIR"
	else
		while read -r line ; do
			echo "$line" >> "$ENTRY_FILE"
		done
	fi
	MERGED_ENTRY_FILE="$(mktemp)"

	HEADERS=$(get_headers "$ENTRY_FILE")
	{
		echo "$HEADERS" | grep -q "^X-Date:" || echo "X-Date: $UTC_TIMESTAMP"
		echo "$HEADERS" | grep -q "^X-Note-Id:" || echo "X-Note-Id: $(uuid)"
		echo "$HEADERS"
		echo "$HEADERS" | grep -q "^Subject:" || echo "Subject: "
		echo ""
		get_body "$ENTRY_FILE"
	} > "$MERGED_ENTRY_FILE"


	mv "$MERGED_ENTRY_FILE" "$ENTRY_FILE"

	pack_mime "$DIR" "$OUTP"

	rm -rf "$DIR"
}

remove_notes_by_id() {
	ID="$1"

	find_files_by_id "$ID" | while read -r FN
	do
		rm "$FN"
	done	
}

notes_equal() {
	NOTE1="$1"
	NOTE2="$2"

	MIME_TYPE1=$(get_header "$NOTE1" Content-Type)
	MIME_TYPE2=$(get_header "$NOTE2" Content-Type)
	BOUNDARY1=$(echo "$MIME_TYPE1" | sed -n 's/^.*boundary="\(.*\)"$/\1/p')
	BOUNDARY2=$(echo "$MIME_TYPE2" | sed -n 's/^.*boundary="\(.*\)"$/\1/p')

	FILTER1="^Date:"
	FILTER2="^Date:"

	if [ -n "$BOUNDARY1" ]; then
		FILTER1="^Date:\|$BOUNDARY1"
	fi

	if [ -n "$BOUNDARY2" ]; then
		FILTER2="^Date:\|$BOUNDARY2"
	fi

	NOTE1_S="$(mktemp)"

	grep -v "$FILTER1" "$NOTE1" > "$NOTE1_S"

	if grep -v "$FILTER2" "$NOTE2" | cmp -s "$NOTE1_S"; then
		rm "$NOTE1_S"
		return 0
	else
		rm "$NOTE1_S"
		return 1
	fi
}

new_entry() {
	OUTP="$(mktemp)"
	input_note "$1" "$OUTP"

	if [ ! -s "$OUTP" ]; then
		rm "$OUTP"
		return
	fi

	NOTE_ID="$(get_header "$OUTP" X-Note-Id)"

	OLD_NOTE="$(find_file_by_id "$NOTE_ID")"
	if [ -n "$OLD_NOTE" ] && notes_equal "$OLD_NOTE" "$OUTP"; then
		return
	fi

	remove_notes_by_id "$NOTE_ID"

	UNIX_TIMESTAMP=$(date "+%s")
	HOSTNAME=$(hostname -s)
	FILENAME="$UNIX_TIMESTAMP.${PID}_1.${HOSTNAME}:2,S"
	mv "$OUTP" "$BASEDIR/cur/$FILENAME"
}


edit_entry() {
	ID="$1"
	FILENAME="$(assert_find_file_by_id "$ID")"

	DIR="$CACHE_DIR/$ID"

	if [ -d "$DIR" ] && [ -f "$DIR/note.md" ]; then
		RESUME_EDITING=$(yesno "Unsaved changes found for this note. Resume editing?" y)		
	fi

	if [ "$RESUME_EDITING" != "y" ]; then
		rm -rf "$DIR"
		mkdir -p "$DIR"
    	unpack_mime "$FILENAME" "$DIR"
	fi

	OLD_DIR="$(pwd)"
	cd "$DIR"
	if ! "$EDITOR" "$DIR/note.md"; then
		die "Editor returned non-zero exit code. Leaving the note untouched."	
	fi
	cd "$OLD_DIR"

	UNIX_TIMESTAMP=$(date "+%s")
	HOSTNAME=$(hostname -s)

	RESULT=$(mktemp)
	pack_mime "$DIR" "$RESULT"

	if ! notes_equal "$RESULT" "$FILENAME"; then
		DEST_FILENAME="$UNIX_TIMESTAMP.${PID}_1.${HOSTNAME}:2,S"
		mv "$RESULT" "$BASEDIR/cur/$DEST_FILENAME"
		rm "$FILENAME"
	fi
	rm -rf "$DIR"
}

list_entries() {
	FILTER="\
		BEGIN { \
			message_id=0; \
			subject=0; \
			date=0; \
		} \
		match(\$0, /^X-Note-Id: .*$/) { \
				if (message_id != 0) { \
					if (subject !=0 && date != 0)\
						print date, message_id, subject; \
					subject = 0; \
					date = 0; \
				};\
				message_id = substr(\$0, 12, RLENGTH-11); \
		} \
		match(\$0, /^Subject: .*$/) { \
				if (subject != 0) { \
					if (message_id != 0 && date != 0)\
						print date, message_id, subject; \
					message_id = 0; \
					date = 0; \
				}; \
				subject = substr(\$0, 10, RLENGTH-9); \
		} \
		match(\$0, /^X-Date: .*$/) { \
				if (date != 0) { \
					if (message_id != 0 && subject != 0)\
						print date, message_id, subject; \
					subject = 0; \
					message_id = 0; \
				}; \
				date = substr(\$0, 9, RLENGTH-8); \
		} \
		END { \
			if (message_id != 0 && subject != 0 && date != 0)\
				print date, message_id, subject;\
		}\
	"

    grep -m3 -r -h "^Subject:\|^X-Note-Id:\|^X-Date:" "$BASEDIR" | awk "$FILTER" | sort | cut -d " " -f "2-"
}

export_note() {
	ID="$1"
	FILENAME="$(assert_find_file_by_id "$ID")"

	DIR="$2"
    unpack_mime "$FILENAME" "$DIR"
}

get_raw_graph() {
	UUID_RE="[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"	
	FILTER="\
		BEGIN { \
			message_id=0; \
			subject=0; \
		} \
		match(\$0, /^X-Note-Id: .*$/) { \
				if (message_id != 0) { \
					if (subject !=0)\
						print \"node\", message_id, subject; \
					subject = 0 \
				};\
				message_id = substr(\$0, 12, RLENGTH-11) \
		} \
		match(\$0, /^Subject: .*$/) { \
				if (subject != 0) { \
					if (message_id != 0)\
						print \"node\", message_id, subject; \
					message_id = 0 \
				}; \
				subject = substr(\$0, 10, RLENGTH-9) \
		} \
		match(\$0, /^note:\/\/.*$/) { \
				link_to = substr(\$0, 8, RLENGTH-7); \
				if (subject != 0 && message_id != 0) { \
					print \"link\", message_id, link_to; \
				}; \
		} \
		END { \
			if (message_id != 0 && subject != 0)\
				print \"node\", message_id, subject;\
		}\
	"
	grep -E -i -o -r -h "^X-Note-Id: $UUID_RE|^Subject.*$|note://$UUID_RE" \
		"$BASEDIR"/cur | awk "$FILTER"
}

get_graph() {
	UUIDLEN=36
	FILTER="\
		BEGIN { \
			print \"graph notes {\" \
		} \
		{\
			if (\$1 == \"node\") {\
				printf \"  \\\"%s\\\" \", \$2;\
				printf \"[label=\\\"%s\\\"]\", substr(\$0, $UUIDLEN + 7, length(\$0) - $UUIDLEN - 5);\
				printf \";\\n\";\
			}\
			if (\$1 == \"link\") {\
				printf \"  \\\"%s\\\" -- \\\"%s\\\";\\n\", \$2, \$3;\
			}\
		}\
		END { \
			print \"}\" \
		} \
	"
	get_raw_graph | sort -r | sed 's/"/\\"/g' | awk "$FILTER"
}

usage() {
  echo "$0 {--new,--list,--edit,--export,--graph,--help}"
}

while (( "$#" )); do
  case "$1" in
    -n|--new)
      new_entry "$2"
      exit 0
      ;;
    -l|--list)
      list_entries
      exit 0
      ;;
    -e|--edit)
      if [ -z "$2" ]; then
        echo "Misssing argument for $1"
        exit 1
      fi
      edit_entry "$2"
      exit 0
      ;;
	-E|--export)
      if [ -z "$2" ] || [ -z "$3" ]; then
        echo "Misssing arguments for $1"
        exit 1
      fi
	  export_note "$2" "$3"
	  exit 0
	  ;;
	-g|--graph)
	  get_graph
	  exit 0
	  ;;
    *)
      usage
      exit 1
      ;;
  esac

done

usage
exit 1
