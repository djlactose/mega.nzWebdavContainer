FROM ubuntu:24.10

ENV username=your@email.com
ENV password=yourPassword
ENV sync=false

VOLUME /mnt

ADD https://mega.nz/linux/repo/xUbuntu_24.10/amd64/megacmd-xUbuntu_24.10_amd64.deb /tmp/mega.deb

EXPOSE 4443

COPY run.sh /root/bin/

RUN apt update && \
apt install -y uuid /tmp/mega.deb

HEALTHCHECK CMD if [ $(mega-webdav |grep -c http) -gt 0 ]; then exit 0; else exit 1;fi

CMD /root/bin/run.sh