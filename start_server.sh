#!/bin/bash

sed -i "s/#LDAP_BIND_DN/${LDAP_BIND_DN}/g" /etc/sasl2/smtpd.conf
sed -i "s/#LDAP_PASSWORD/${LDAP_PASSWORD}/g" /etc/sasl2/smtpd.conf
sed -i "s/#LDAP_SEARCH_BASE/${LDAP_SEARCH_BASE}/g" /etc/sasl2/smtpd.conf
sed -i "s/#LDAP_SERVERS/${LDAP_SERVERS}/g" /etc/sasl2/smtpd.conf
saslauthd -m /run/saslauthd -a ldap -O /etc/sasl2/smtpd.conf
echo ${TRANSPORT} > /etc/postfix/transport
echo ${ALIASES} > /etc/postfix/aliases
#postalias lmdb:/etc/postfix/aliases
postalias hash:/etc/postfix/aliases
#postmap lmdb:/etc/postfix/header_checks
#postmap lmdb:/etc/postfix/transport
postmap hash:/etc/postfix/header_checks
postmap hash:/etc/postfix/transport
#postmap lmdb:/etc/postfix/virtual
postconf compatibility_level=2
postconf inet_interfaces=all
postconf maillog_file=/var/log/postfix.log
postconf myhostname=${MYHOSTNAME}
postconf mynetworks=${MYNETWORKS}
postconf relayhost=${RELAYHOST}
postconf always_bcc=${ALWAYS_BCC}
touch /var/log/postfix.log
#ln -sf /proc/1/fd/1 /var/log/postfix.log
/usr/sbin/postfix start-fg