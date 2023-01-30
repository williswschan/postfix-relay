#!/bin/bash

#set -e				# Bash to stop execution instantly as a query exits while having a non-zero status.
#set -o pipefail	# Bash to stop execution instantly as a query exits while having a non-zero status.

cp -nR /etc/postfix.bak/* /etc/postfix
chmod go-w /etc/postfix/				# This is due to K8S PersistentVolume doesn't do overlay for exposed volume
rm -rf /etc/postfix.bak

cat > /etc/postfix/main.cf <<EOF
alias_database = hash:/etc/postfix/aliases
alias_maps = hash:/etc/postfix/aliases	
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
#inet_protocols = all
mail_owner = postfix
mailq_path = /usr/bin/mailq.postfix
# maillog managed by rsyslog
maillog_file =
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
smtpd_sasl_auth_enable=no
smtpd_sasl_security_options = noanonymous
smtpd_sasl_type = cyrus
#smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated, reject
smtpd_sender_restrictions = permit_mynetworks, permit_sasl_authenticated
smtpd_tls_cert_file = /etc/pki/tls/certs/postfix.pem
smtpd_tls_key_file = /etc/pki/tls/private/postfix.key
smtpd_tls_security_level = may
transport_maps = hash:/etc/postfix/transport
unknown_local_recipient_reject_code = 550
EOF

shopt -s nocasematch
if [[ "$PWCHECK_METHOD" == "LDAP" ]] && [ "${LDAP_SERVERS}" ] && [ "${LDAP_SEARCH_BASE}" ] && [ "${LDAP_BIND_DN}" ] && [ "${LDAP_PASSWORD}" ]; then
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
	postconf smtpd_sasl_auth_enable=yes
	saslauthd -m /run/saslauthd -a ldap -O /etc/sasl2/smtpd.conf
elif [[ "$PWCHECK_METHOD" == "SHADOW" ]] && [ "${SHADOW_USERNAME}" ] && [ "${SHADOW_PASSWORD}" ]; then
cat > /etc/sasl2/smtpd.conf <<EOF
pwcheck_method: saslauthd
mech_list: PLAIN LOGIN
EOF
	useradd "${SHADOW_USERNAME}"; echo -e "${SHADOW_PASSWORD}" | passwd "${SHADOW_USERNAME}" --stdin
	postconf smtpd_sasl_auth_enable=yes
	saslauthd -m /run/saslauthd -a shadow -O /etc/sasl2/smtpd.conf
fi
shopt -u nocasematch

cat > /etc/postfix/header_checks <<EOF
/^Subject:/     		WARN
/^Received:.*/	     	IGNORE
/^X-Originating-IP:/    IGNORE
EOF

cat > /etc/sysconfig/saslauthd <<EOF
SOCKETDIR=/run/saslauthd
MECH=ldap
FLAGS=-O /etc/sasl2/smtpd.conf
EOF

cat > /etc/logrotate.d/postfix <<EOF
/var/log/maillog {
	daily
    rotate 60
    missingok
    ifempty
    sharedscripts
    nocompress
#	nocopytruncate
	nomail
	noolddir
    postrotate
        postfix reload > /dev/null 2>/dev/null || true
    endscript
}
EOF

cat > /etc/rsyslog.conf <<EOF
module(load="imuxsock"    # provides support for local system logging (e.g. via logger command)
       SysSock.Use="on")  # Turn on message reception via local log socket;
                          # local messages are not retrieved through imjournal now.
global(workDirectory="/var/lib/rsyslog")
module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat")
include(file="/etc/rsyslog.d/*.conf" mode="optional")
if (\$programname contains "postfix") and (\$msg contains "internal.cloudapp.net") and not (\$msg contains "Subject") then {
   stop
}
*.info;mail.none;authpriv.none;cron.none                /var/log/messages
authpriv.*                                              /var/log/secure
mail.*                                                  -/var/log/maillog
mail.*													${SYSLOG}
cron.*                                                  /var/log/cron
*.emerg                                                 :omusrmsg:*
uucp,news.crit                                          /var/log/spooler
local7.*                                                /var/log/boot.log
EOF

cp /etc/resolv.conf /etc/resolv.conf.bak
if [ "${DNS}" ]
then
	yes | cp /etc/resolv.conf.bak /etc/resolv.conf
	grep -v "^nameserver" /etc/resolv.conf | tee /etc/resolv.conf
	IFS=',' ;for i in `echo "${DNS}"`; do echo nameserver $i | xargs >> /etc/resolv.conf; done
fi
if [ "${ALIASES}" ]
then
	cat /dev/null > /etc/postfix/aliases
	IFS='/' ;for i in `echo "${ALIASES}"`; do echo $i | xargs >> /etc/postfix/aliases; done
fi
touch /etc/postfix/aliases
postalias hash:/etc/postfix/aliases
if [ "${TRANSPORT}" ]
then
	cat /dev/null > /etc/postfix/transport
	IFS=',' ;for i in `echo "${TRANSPORT}"`; do echo $i | xargs >> /etc/postfix/transport; done
	postmap hash:/etc/postfix/transport
fi
touch /etc/postfix/transport
postmap hash:/etc/postfix/transport
if [ "${HEADER_CHECKS}" ] && [ "${HEADER_CHECKS}" != "0" ]
then
	postconf header_checks=regexp:/etc/postfix/header_checks
	postmap hash:/etc/postfix/header_checks
else
	postconf header_checks=
	postmap hash:/etc/postfix/header_checks
fi
#postmap hash:/etc/postfix/virtual
if [ "${RATE_LIMIT}" ]; then postconf smtpd_client_message_rate_limit=${RATE_LIMIT}; else postconf smtpd_client_message_rate_limit=0; fi
yes | cp /etc/postfix/master.cf.bak /etc/postfix/master.cf
if [ "${DEFAULT_SMTP_PORT}" ]; then grep "^smtp.*smtpd$" /etc/postfix/master.cf | sed "s/^smtp/${DEFAULT_SMTP_PORT}/g" >> /etc/postfix/master.cf; fi
if [ "${MYHOSTNAME}" ]; then postconf myhostname="${MYHOSTNAME}"; fi
if [ "${RELAY_DOMAINS}" ]; then postconf relay_domains="${RELAY_DOMAINS}"; fi
postconf mynetworks="${MYNETWORKS}"
postconf relayhost="${RELAYHOST}"
postconf always_bcc="${ALWAYS_BCC}"

#postconf maillog_file=/dev/stdout
#postconf maillog_file=/var/log/postfix.log
#ln -sf /proc/1/fd/1 /var/log/postfix.log

/usr/sbin/crond -m off
/usr/sbin/rsyslogd
/usr/sbin/postfix start

touch /var/log/maillog
tail -F /var/log/maillog >> /dev/stdout		# Non-terminated process need to be placed at the end.
