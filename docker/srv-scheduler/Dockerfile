FROM ruby:2.4-stretch
MAINTAINER "Christoph Fabianek" christoph@ownyourdata.eu

RUN mkdir /usr/src/app
WORKDIR /usr/src/app
RUN useradd docker \
        && mkdir /home/docker \
        && chown docker:docker /home/docker \
        && addgroup docker staff
USER docker

RUN gem install \
	httparty \
	rufus-scheduler \
	bunny

COPY . .
COPY run.sh /bin/run.sh

EXPOSE 4369 5671 5672 25672

CMD [ "/bin/bash" ]
