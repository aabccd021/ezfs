# ezfs

Easy ZFS configuration for NixOS

# TODO

- disallow encryption off
- force use sops for encryption key
- dataset `enable` set to false by default
- hostId required for pulltarget and pushtarget
- test dependson with alphabetical order
- assert no failed service on test
- assert `dependsOn` dataset actually exists
- server --pull-> homeserver --pull-> desktop
- server --pull-> desktop --push-> vps
- more push test
- create single `ezfs` command reading from json config file
- limit commands can be executed by backup user
