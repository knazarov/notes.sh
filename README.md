# notes.sh: plain-text notes with IMAP synchronization

This project allows you to keep plaintext notes, and attach files to them (like images, PDFs, etc). The plaintext stays plaintext, easily greppable, and with every note in its own file.

What makes it special is that it uses a Maildir format to store notes. This allows you to easily sync your notes with any mail server, and have your notes accessible on the go through your email client.

NB: This is alpha software, use with caution.

## Usage

By default, `notes.sh` will create new entries in `~/Maildir/personal/Notes`, which you can override by setting `$NOTES_SH_BASEDIR`.

To create a new note (will open a new editor window):

```sh
./note.sh -n 
```

To list all existing notes with their titles:

```sh
./note.sh -l
```

To select a note with fuzzy search and edit it:

```sh
./notes.sh -l | fzf --with-nth="2..-1" | xargs -o ./notes.sh -e
```
