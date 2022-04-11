#!/usr/bin/env sh


chown -R dovecot /Maildir
exec /usr/sbin/dovecot -F