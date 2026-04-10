FROM --platform=linux/amd64 ubuntu:22.04 AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc

ADD . /cproc
WORKDIR /cproc
RUN ./configure && make

RUN mkdir -p /deps
RUN ldd /cproc/cproc-qbe | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:22.04 AS package

COPY --from=builder /deps /deps
COPY --from=builder /cproc/cproc-qbe /cproc/cproc-qbe
ENV LD_LIBRARY_PATH=/deps
