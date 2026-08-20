# Local addon data

Run `./local-data/update-data.sh` from anywhere in the repository to copy the
`RSH_` SavedVariables files from the local World of Warcraft installation into
this directory.

Use `/reload` or log out in World of Warcraft first so the files on disk contain
the latest addon data. The copied `.lua` and `.lua.bak` files are ignored by Git.
