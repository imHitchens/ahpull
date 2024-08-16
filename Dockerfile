FROM alpine:latest
USER root
WORKDIR /
ADD . .
RUN apk add --update bash && echo 1
RUN apk add --update curl && echo 2
RUN apk add --update jq  && echo 3
ENTRYPOINT ["bash", "ahpull.sh"]
