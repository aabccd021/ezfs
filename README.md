# ezfs

Easy ZFS configuration for NixOS

# Limitations

- Only encrypted datasets are supported

# TODO

- force use agenix for encryption key
- dataset `enable` set to false by default
- hostId required for pulltarget and pushtarget
- assert no failed service on test
- server --pull-> homeserver --pull-> desktop
- server --pull-> desktop --push-> vps
- more push test
- create single `ezfs` command reading from json config file
- limit commands can be executed by backup user
