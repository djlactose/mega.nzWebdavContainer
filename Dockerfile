FROM centos:8

ENV username your@email.com
ENV password yourPassword

ADD https://mega.nz/linux/MEGAsync/CentOS_8/x86_64/megacmd-CentOS_8.x86_64.rpm /tmp/mega.rpm

EXPOSE 4443

COPY run.sh /root/bin/

RUN dnf install /tmp/mega.rpm -y

HEALTHCHECK CMD if [ $(mega-webdav |grep -c http) -gt 0 ]; then echo 0; else echo 1;fi

CMD /root/bin/run.sh