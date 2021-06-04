#! /usr/bin/env python
import shutil
import sys
import emoji
import tempfile

fout = tempfile.NamedTemporaryFile(delete=False)
with open(sys.argv[1], "r") as f_in:
    print("Emojifying ", sys.argv[1])
    for line in f_in.readlines():
        fout.write(emoji.emojize(line, use_aliases=True).encode('utf-8'))
shutil.move(fout.name, sys.argv[1])
