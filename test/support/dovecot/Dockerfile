FROM debian:latest

RUN apt-get update && apt-get install -y \
    dovecot-core \
    dovecot-imapd

RUN usermod -u 1026 dovecot

COPY ./Maildir /Maildir
COPY ./dovecot.conf /etc/dovecot/dovecot.conf
COPY ./passwd /etc/dovecot/passwd
COPY entrypoint.sh /entrypoint.sh

RUN chmod u+x /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]