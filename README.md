# ezfs

Easy ZFS configuration for NixOS

# TODO

- fix `zfs-import-zroot`, some service needs to require it
- test dependson with alphabetical order
- push to node2
- assert no failed service on test
- assert `dependsOn` dataset actually exists
- server --pull-> homeserver --pull-> desktop
- server --pull-> desktop --push-> vps
- more push test
- create single `ezfs` command reading from json config file
- limit commands can be executed by backup user
