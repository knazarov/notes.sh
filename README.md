# notes.sh: plain-text notes with IMAP synchronization

This note taking system is built for people who care about minimalism and want their software to last for decades. It is a single shell script that organizes all your plain-text notes insize a directory in a Maildir format. It is also editor-agnostic, so you can use vim, emacs or whichever you are comfortable with. Syncing between computers is trivial: just use any tool (like isync) that can sync a Maildir to any email hosting.

Maildir was created to store e-mail on a mail server/client, but is perfectly fine to store any kind of text. It saves every entry as a separate file in a MIME format. MIME in its simplest form is a few lines of "headers" followed by a plain-text content. It also has a feature to add attachments to the same file, by encoding them in base64.

Even if you see that this repository hasn't been updated for a long time, rest assured that it still works. Its only dependencies are standard POSIX tools.

## Features

- Keep notes in a single Maildir (by default in `~/Maildir/personal/Notes`
- Sync your notes with any email server, from multiple devices
- Specify the editor to use by changing `$EDITOR` environment variable
- Notes are identified by a unique ID
- You can link between notes using their IDs and create a knowledge graph
- There is support for adding attachments like images, PDFs, and other
- Small codebase, so very easy to read through and extend to your liking
- Zero dependencies, except for POSIX tools

## Installation

Copy `notes.sh` script anywhere in your `$PATH`.

## Usage

By default, `notes.sh` will create new entries in `~/Maildir/personal/Notes`, which you can override by setting `$NOTES_SH_BASEDIR`.

To create a new note (will open a new editor window):

```sh
./notes.sh -n 
```

To list all existing notes with their titles:

```sh
./notes.sh -l
```

To select a note with fuzzy search and edit it:

```sh
./notes.sh -l | fzf --tac --with-nth="2..-1" | xargs -o ./notes.sh -e
```

## License

Distributed under the terms of the BSD License
