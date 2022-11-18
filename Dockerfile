FROM centos:7

ENV username your@email.com
ENV password yourPassword

ADD https://mega.nz/linux/MEGAsync/CentOS_7/x86_64/megacmd-1.5.1-2.1.x86_64.rpm /tmp/mega.rpm

EXPOSE 4443

COPY run.sh /root/bin/

RUN yum localinstall /tmp/mega.rpm -y

HEALTHCHECK CMD if [ $(mega-webdav |grep -c http) -gt 0 ]; then exit 0; else exit 1;fi

CMD /root/bin/run.sh