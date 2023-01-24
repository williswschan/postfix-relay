#FROM alpine:3.16
FROM centos:latest

# Command for Alpine
#RUN apk update && \
#    apk add postfix postfix-ldap tzdata && \
#    rm -rf /var/cache/apk/*

# Command for CentOS
RUN cd /etc/yum.repos.d/
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

RUN dnf -y install postfix postfix-ldap tzdata cyrus-sasl cyrus-sasl-plain openldap && \
	dnf clean all

COPY main.cf /etc/postfix
#COPY Dockerfile /etc/postfix		# For further reference
COPY saslauthd /etc/sysconfig
#COPY smtpd.conf /etc/sasl2
COPY start_server.sh /opt
COPY header_checks /etc/postfix/

RUN chmod 755 /opt/start_server.sh

EXPOSE 25/tcp
#EXPOSE 465/tcp
#EXPOSE 587/tcp

# May mount the config volume if extra setting is required
#VOLUME ["/etc/postfix"]
#VOLUME ["/var/log"]

CMD /opt/start_server.sh
