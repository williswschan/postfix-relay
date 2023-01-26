#!/bin/bash

#set -e
#set -o pipefail

cat > /etc/sasl2/smtpd.conf <<EOF
pwcheck_method: saslauthd
mech_list: plain login
ldap_servers: ldap://${LDAP_SERVERS}
ldap_search_base: ${LDAP_SEARCH_BASE}
ldap_timeout: 10
ldap_filter: sAMAccountName=%U
ldap_bind_dn: ${LDAP_BIND_DN}
ldap_password: ${LDAP_PASSWORD}
ldap_deref: never
ldap_restart: yes
ldap_scope: sub
ldap_use_sasl: no
ldap_start_tls: no
ldap_version: 3
ldap_auth_method: bind
EOF

cat > /etc/postfix/header_checks <<EOF
/^Received:.*/	     	IGNORE
/^X-Originating-IP:/    IGNORE
EOF

cat > /etc/postfix/main.cf <<EOF
broken_sasl_auth_clients = yes
compatibility_level = 2
command_directory = /usr/sbin
daemon_directory = /usr/libexec/postfix
data_directory = /var/lib/postfix
debug_peer_level = 2
debugger_command = PATH=/bin:/usr/bin:/usr/local/bin:/usr/X11R6/bin ddd $daemon_directory/$process_name $process_id & sleep 5
html_directory = no
inet_interfaces = all
inet_protocols = ipv4
mail_owner = postfix
mailq_path = /usr/bin/mailq.postfix
manpage_directory = /usr/share/man
myhostname = smtp-out.contoso.com
mydestination = \$myhostname, localhost.\$mydomain, localhost
mynetworks =
newaliases_path = /usr/bin/newaliases.postfix
queue_directory = /var/spool/postfix
readme_directory = /usr/share/doc/postfix-2.10.1/README_FILES
sample_directory = /usr/share/doc/postfix-2.10.1/samples
sendmail_path = /usr/sbin/sendmail.postfix
setgid_group = postdrop
smtp_tls_security_level = may
smtpd_client_restrictions = permit_mynetworks, permit_sasl_authenticated
smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_sasl_authenticated_header = no
smtpd_sasl_security_options = noanonymous
smtpd_sasl_type = cyrus
smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated, reject
smtpd_tls_cert_file = /etc/pki/tls/certs/postfix.pem
smtpd_tls_key_file = /etc/pki/tls/private/postfix.key
smtpd_tls_security_level = may
transport_maps = hash:/etc/postfix/transport
unknown_local_recipient_reject_code = 550
EOF

cat > /etc/sysconfig/saslauthd <<EOF
SOCKETDIR=/run/saslauthd
MECH=ldap
FLAGS=-O /etc/sasl2/smtpd.conf
EOF

cat > /etc/logrotate.d/postfix <<EOF
/var/log/postfix.log {
	daily
    rotate 60
    missingok
    ifempty
    sharedscripts
    nocompress
#	nocopytruncate
	nomail
	noolddir
#    postrotate
#        postfix reload > /dev/null 2>/dev/null || true
#    endscript
}
EOF

if [ "${DNS}" ]
then
	yes | cp /etc/resolv.conf.bak /etc/resolv.conf
	IFS=',' ;for i in `echo "${DNS}"`; do echo nameserver $i | xargs >> /etc/resolv.conf; done
fi
if [ "${ALIASES}" ]
then
	cat /dev/null > /etc/postfix/aliases
	IFS='/' ;for i in `echo "${ALIASES}"`; do echo $i | xargs >> /etc/postfix/aliases; done
	postalias hash:/etc/postfix/aliases
	postconf alias_database=hash:/etc/postfix/aliases
	postconf alias_maps=hash:/etc/postfix/aliases	
fi
if [ "${TRANSPORT}" ]
then
	cat /dev/null > /etc/postfix/transport
	IFS=',' ;for i in `echo "${TRANSPORT}"`; do echo $i | xargs >> /etc/postfix/transport; done
	postmap hash:/etc/postfix/transport
fi
if [ "${HEADER_CHECKS}" ]
then
	postconf header_checks=regexp:/etc/postfix/header_checks
	postmap hash:/etc/postfix/header_checks
else
	postconf header_checks=
	postmap hash:/etc/postfix/header_checks
fi

#postmap hash:/etc/postfix/virtual

if [ "${RATE_LIMIT}" ]; then postconf smtpd_client_message_rate_limit=${RATE_LIMIT}; else postconf smtpd_client_message_rate_limit=0; fi
if [ "${LDAP_SERVERS}" ] && [ "${LDAP_SEARCH_BASE}" ] && [ "${LDAP_BIND_DN}" ] && [ "${LDAP_PASSWORD}" ]
then
#	sed -i "s/#LDAP_SERVERS/${LDAP_SERVERS}/g" /etc/sasl2/smtpd.conf
#	sed -i "s/#LDAP_SEARCH_BASE/${LDAP_SEARCH_BASE}/g" /etc/sasl2/smtpd.conf
#	sed -i "s/#LDAP_BIND_DN/${LDAP_BIND_DN}/g" /etc/sasl2/smtpd.conf
#	sed -i "s/#LDAP_PASSWORD/$(echo -e ${LDAP_PASSWORD} | sed "s|\&|\\\&|g")/g" /etc/sasl2/smtpd.conf		# Need to escape any ampersand(&) or sed won't work.
	saslauthd -m /run/saslauthd -a ldap -O /etc/sasl2/smtpd.conf
	postconf smtpd_sasl_auth_enable=yes
else
	postconf smtpd_sasl_auth_enable=no
fi
yes | cp /etc/postfix/master.cf.bak /etc/postfix/master.cf
if [ "${DEFAULT_SMTP_PORT}" ]; then grep "^smtp.*smtpd$" /etc/postfix/master.cf | sed -i "s/^smtp/${DEFAULT_SMTP_PORT}/g" /etc/postfix/master.cf; fi
if [ "$MYHOSTNAME" ]; then postconf myhostname="${MYHOSTNAME}"; fi
postconf mynetworks="${MYNETWORKS}"
postconf relayhost="${RELAYHOST}"
postconf always_bcc="${ALWAYS_BCC}"
#postconf maillog_file=/dev/stdout
postconf maillog_file=/var/log/postfix.log

touch /var/log/postfix.log
#ln -sf /proc/1/fd/1 /var/log/postfix.log

/usr/sbin/crond -m off
#/usr/sbin/postfix start-fg &
/usr/sbin/postfix start

tail -F /var/log/postfix.log >> /dev/stdout		# Non-terminated process need to be placed at the end.
