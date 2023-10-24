#!/bin/bash
usernames=("martintoreilly" "JimMadge" "edwardchalstrey1" "craddm" "tomdoel" "OscartGiles" "james-c" "miguelmorin" "cathiest" "bw-faststream" "RobC-CT" "oforrest" "jamespjh" "warwick26" "KirstieJane" "thobson88" "ens-george-holmes" "fedenanni" "tomaslaz" "rwinstanley1" "sysdan" "ACabrejas" "harisood" "getcarter21" "christopheredsall" "ens-brett-todd" "darenasc" "kevinxufs" "vollmersj" "callummole" "JulesMarz" "DavidBeavan" "gn5" "jack89roberts")
for name in "${usernames[@]}"; do
  yarn all-contributors add "$name" code,doc
done
