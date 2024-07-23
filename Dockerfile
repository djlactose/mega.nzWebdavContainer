FROM ubuntu:24.04

ENV username=your@email.com
ENV password=yourPassword
ENV sync=false

VOLUME /mnt

ADD https://mega.nz/linux/repo/xUbuntu_24.04/amd64/megacmd_1.7.0-6.1_amd64.deb /tmp/mega.deb

EXPOSE 4443

COPY run.sh /root/bin/

RUN apt update && \
apt install -y uuid /tmp/mega.deb

HEALTHCHECK CMD if [ $(mega-webdav |grep -c http) -gt 0 ]; then exit 0; else exit 1;fi

CMD /root/bin/run.sh