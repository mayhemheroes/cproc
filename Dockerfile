FROM --platform=linuxamd64 ubuntu:20.04
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y make gcc

ADD . /cproc
WORKDIR /cproc/qbe
RUN make
ENV PATH=/cproc/qbe/obj:$PATH
WORKDIR /cproc
RUN make
