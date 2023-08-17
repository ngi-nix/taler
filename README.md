# A flake for running GNU Taler

Implemented as NixOS modules
- [x] taler-exchange
- [ ] taler-merchant
- [ ] libeufin

There is now apparently enough database setup that some taler-exchange
daemons start. Others however lack credit/debit account info which is
not documented.

There is a Debian template that can be used as a reference:
https://git.taler.net/marketing.git/tree/2023-fsf/walkthrough.sh
