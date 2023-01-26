#FROM alpine:3.16
FROM centos:latest

MAINTAINER Willis Chan <willis.chan@mymsngroup.com>
# Thu Jan 26 20:41:36 HKT 2023

ENV TZ=Asia/Hong_Kong

# Command for Alpine
#RUN apk update && \
#    apk add postfix postfix-ldap tzdata && \
#    rm -rf /var/cache/apk/*

# Command for CentOS
RUN cd /etc/yum.repos.d/
RUN sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
RUN sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

RUN dnf -y update
RUN dnf -y install postfix postfix-ldap tzdata cyrus-sasl cyrus-sasl-plain openldap cronie logrotate && dnf clean all

WORKDIR /opt

#COPY main.cf /etc/postfix
#COPY saslauthd /etc/sysconfig
#COPY smtpd.conf /etc/sasl2
#COPY header_checks /etc/postfix/
COPY Dockerfile Dockerfile
COPY start_server.sh start_server.sh

RUN chmod +x /opt/start_server.sh
RUN cp /etc/postfix/master.cf /etc/postfix/master.cf.bak
RUN cp /etc/resolv.conf /etc/resolv.conf.bak

#RUN crontab -l | { cat; echo "* * * * * bash /root/get_date.sh"; } | crontab -
#RUN crontab -l | { cat; echo "* * * * * date >> /var/log/dummy.log"; } | crontab -

EXPOSE 25/tcp
#EXPOSE 465/tcp
#EXPOSE 587/tcp

# May mount the config volume if extra setting is required
#VOLUME ["/var/log"]
#VOLUME ["/etc/postfix/cert"]
#VOLUME ["/etc/postfix"]

CMD /opt/start_server.sh
