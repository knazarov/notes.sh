#!/bin/bash

set -e

DATE_FORMAT="%a, %d %b %Y %H:%M:%S %z"
PID=$$
BASEDIR=~/Maildir/personal/Notes

if [ -n "$NOTES_SH_BASEDIR" ]; then
	BASEDIR="$NOTES_SH_BASEDIR"
fi

if [ -z "$EDITOR" ]; then
	EDITOR=vim
fi

if [ ! -d "$BASEDIR" ]; then
	mkdir -p "$BASEDIR"/{tmp,new,cur}
fi

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
	MESSAGE_ID=$(get_header "$FILE" Message-Id)

	echo "Date: $DATE" > "$DIR/note.md"
	if [ -n "$MESSAGE_ID" ]; then
		echo "Message-Id: $MESSAGE_ID" >> "$DIR/note.md"
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
	DIR=$(mktemp -d)
	ENTRY_FILE="$DIR/note.md"
	ENTRY_FILE_START="$(mktemp)"
	MIME_TIMESTAMP=$(LC_ALL="en_US.UTF-8" date "+$DATE_FORMAT")

	cat > "$ENTRY_FILE" <<- EOF
		Date: $MIME_TIMESTAMP
		Message-Id: <$(uuid)@notes.sh>
		Subject: 
	EOF

	cp "$ENTRY_FILE" "$ENTRY_FILE_START"

	if [ -t 0 ]; then
		"$EDITOR" "$ENTRY_FILE"
	else
		ENTRY_FILE_STDIN="$(mktemp)"
		while read -r line ; do
			echo "$line" >> "$ENTRY_FILE_STDIN"
		done

		HEADERS=$( echo "$(
			get_headers "$ENTRY_FILE_STDIN"
			get_headers "$ENTRY_FILE"
			)" | sort -u -k1,1)

		{
			echo "$HEADERS"
			echo ""
			get_body "$ENTRY_FILE_STDIN"
		} > "$ENTRY_FILE"
	fi

	if  ! cmp -s "$ENTRY_FILE" "$ENTRY_FILE_START" ; then
		UNIX_TIMESTAMP=$(date "+%s")
		HOSTNAME=$(hostname -s)

		RESULT=$(mktemp)
		pack_mime "$DIR" "$RESULT"
		FILENAME="$UNIX_TIMESTAMP.${PID}_1.${HOSTNAME}:2,S"
		mv "$RESULT" "$BASEDIR/cur/$FILENAME"
	fi
}

edit_entry() {
	FILENAME="$(echo "$1" | sed 's/\o037.*//' )"

	DIR=$(mktemp -d)
    unpack_mime "$FILENAME" "$DIR"
	"$EDITOR" "$DIR/note.md"

	UNIX_TIMESTAMP=$(date "+%s")
	HOSTNAME=$(hostname -s)

	RESULT=$(mktemp)
	pack_mime "$DIR" "$RESULT"

	if ! cmp -s "$RESULT" "$FILENAME"; then
		DEST_FILENAME="$UNIX_TIMESTAMP.${PID}_1.${HOSTNAME}:2,S"
		mv "$RESULT" "$BASEDIR/cur/$DEST_FILENAME"
		rm "$FILENAME"
	fi
}

list_entries() {
	grep -m1 -r "^Subject:" "$BASEDIR" | sed -n 's/^\(.*\):Subject: \(.*\)$/\1\o037 \2/p'

}

usage() {
  echo "$0 {--new,--list,--edit,--help}"
}


while (( "$#" )); do
  case "$1" in
    -n|--new)
      new_entry
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
    *)
      usage
      exit 1
      ;;
  esac

done

usage
exit 1
