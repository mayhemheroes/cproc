FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc

ADD . /cproc
WORKDIR /cproc/qbe
RUN make
ENV PATH=/cproc/qbe/obj:$PATH
WORKDIR /cproc
RUN make

RUN mkdir -p /deps
RUN ldd /cproc/cproc-qbe | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /cproc/cproc-qbe /cproc/cproc-qbe
ENV LD_LIBRARY_PATH=/deps
