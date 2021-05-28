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

yesno() {
	PROMPT="$1"
	DEFAULT="$2"

	if [[ "$DEFAULT" == "y" ]]; then
		read -p "$PROMPT [Y/n] " -r CHOICE
		if [[ "$REPLY" =~ ^[Nn]$ ]]; then
			echo "n"
		else
			echo "y"
		fi
	else
		read -p "$PROMPT [y/N] " -r CHOICE
		if [[ "$REPLY" =~ ^[Yy]$ ]]; then
			echo "y"
		else
			echo "n"
		fi
	fi
}

get_headers() {
	FILE="$1"
	
	FILTER="\
		{ \
		    if (\$0~/^$/) {exit} \
		    print \$0 \
		} \
	"
	awk "$FILTER" "$FILE"
}

get_body() {
	FILE="$1"
	
	FILTER="\
		{ \
		    if (body==1) {print \$0}\
		    if (\$0~/^$/) {body=1} \
		} \
	"
	awk "$FILTER" "$FILE" 
}
get_header() {
	FILE="$1"
	HEADER="$2"
	grep -m1 "^${HEADER}: " < "$FILE" | sed -n "s/^${HEADER}: \(.*\)$/\1/p"
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
			sed -n 's/^.*filename="\{0,1\}\(.*\)"\{0,1\}$/\1/p')
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

	DATE=$(get_header "$FILE" Date)
	SUBJECT=$(get_header "$FILE" Subject)
	MIME_TYPE=$(get_header "$FILE" Content-Type)
	NOTE_ID=$(get_header "$FILE" X-Note-Id)

	echo "Date: $DATE" > "$DIR/note.md"
	if [ -n "$NOTE_ID" ]; then
		echo "X-Note-Id: $NOTE_ID" >> "$DIR/note.md"
	fi
	echo "Subject: $SUBJECT" >> "$DIR/note.md"
	echo "" >> "$DIR/note.md"

	TMP=$(mktemp --tmpdir="$DIR")
	cat "$FILE" > "$TMP"

	(unpack_part "$TMP" "$DIR")
	rm "$TMP"
}

pack_mime() {
	DIR="$1"
	FILE="$2"
	{
		echo "MIME-Version: 1.0"
		echo "Content-Type: text/plain; charset=utf-8"
		echo "Content-Disposition: inline"
		cat "$DIR/note.md"
	} >> "$FILE"

}

new_entry() {
	INP="$1"
	DIR=$(mktemp -d)
	ENTRY_FILE="$DIR/note.md"
	ENTRY_FILE_START="$(mktemp)"
	MIME_TIMESTAMP=$(LC_ALL="en_US.UTF-8" date "+$DATE_FORMAT")

	cat > "$ENTRY_FILE" <<- EOF
		Date: $MIME_TIMESTAMP
		X-Note-Id: $(uuid)
		Subject: 
	EOF

	cp "$ENTRY_FILE" "$ENTRY_FILE_START"

	if [ -n "$INP" ] && [ ! -f "$INP" ] && [ ! -d "$INP" ]; then
		die "File or directory doesn't exist: $INP"
	fi

	if [ -f "$INP" ]; then
		cp "$INP" "$DIR/note.md"
	elif [ -d "$INP" ]; then
		if [ ! -f "$INP/note.md" ]; then
			die "File doesn't exist: $INP/note.md"
		fi
		cp -n "$INP"/* "$DIR/" || true
		cat "$INP/note.md" >> "$DIR/note.md"
	elif [ -t 0 ]; then
		"$EDITOR" "$ENTRY_FILE"
	else
		while read -r line ; do
			echo "$line" >> "$ENTRY_FILE"
		done
	fi
	MERGED_ENTRY_FILE="$(mktemp)"

	HEADERS=$( echo "$(
		get_headers "$ENTRY_FILE"
		)" | tac | sort -u -k1,1)

	{
		echo "$HEADERS"
		echo ""
		get_body "$ENTRY_FILE"
	} > "$MERGED_ENTRY_FILE"

	mv "$MERGED_ENTRY_FILE" "$ENTRY_FILE"

	if  ! cmp -s "$ENTRY_FILE" "$ENTRY_FILE_START" ; then
		UNIX_TIMESTAMP=$(date "+%s")
		HOSTNAME=$(hostname -s)

		RESULT=$(mktemp)
		pack_mime "$DIR" "$RESULT"
		FILENAME="$UNIX_TIMESTAMP.${PID}_1.${HOSTNAME}:2,S"
		mv "$RESULT" "$BASEDIR/cur/$FILENAME"
	fi
}

find_file_by_id() {
	ID="$1"

	FILE="$( { grep -l -r "^X-Note-Id: $ID$" "$BASEDIR" || true; } | head -1)"

	if [ ! -f "$FILE" ]; then
		die "Note with ID <$ID> not found"
	fi

	echo "$FILE"
}

edit_entry() {
	ID="$1"
	FILENAME="$(find_file_by_id "$ID")"

	DIR="$CACHE_DIR/$ID"

	if [ -d "$DIR" ] && [ -f "$DIR/note.md" ]; then
		RESUME_EDITING=$(yesno "Unsaved changes found for this note. Resume editing?" y)		
	fi

	if [ "$RESUME_EDITING" != "y" ]; then
		rm -rf "$DIR"
		mkdir -p "$DIR"
    	unpack_mime "$FILENAME" "$DIR"
	fi

	if ! "$EDITOR" "$DIR/note.md"; then
		die "Editor returned non-zero exit code. Leaving the note untouched."	
	fi

	UNIX_TIMESTAMP=$(date "+%s")
	HOSTNAME=$(hostname -s)

	RESULT=$(mktemp)
	pack_mime "$DIR" "$RESULT"

	if ! cmp -s "$RESULT" "$FILENAME"; then
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
		} \
		match(\$0, /^X-Note-Id: .*$/) { \
				if (message_id != 0) { \
					if (subject !=0)\
						print message_id, subject; \
					subject = 0 \
				};\
				message_id = substr(\$0, 12, RLENGTH-11) \
		} \
		match(\$0, /^Subject: .*$/) { \
				if (subject != 0) { \
					if (message_id != 0)\
						print message_id, subject; \
					message_id = 0 \
				}; \
				subject = substr(\$0, 10, RLENGTH-9) \
		} \
		END { \
			if (message_id != 0 && subject != 0)\
				print message_id, subject;\
		}\
	"

    grep -m2 -r -h "^Subject:\|^X-Note-Id:" "$BASEDIR" | awk "$FILTER"
}

export_note() {
	ID="$1"
	FILENAME="$(find_file_by_id "$ID")"

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
