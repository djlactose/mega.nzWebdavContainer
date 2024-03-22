FROM ubuntu:23.10

ENV username your@email.com
ENV password yourPassword

ADD https://mega.nz/linux/repo/xUbuntu_23.10/amd64/megacmd-xUbuntu_23.10_amd64.deb /tmp/mega.deb

EXPOSE 4443

COPY run.sh /root/bin/

RUN apt update && \
apt install -y /tmp/mega.deb

HEALTHCHECK CMD if [ $(mega-webdav |grep -c http) -gt 0 ]; then exit 0; else exit 1;fi

CMD /root/bin/run.sh