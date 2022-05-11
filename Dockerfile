# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y vim less man wget tar git gzip unzip make cmake software-properties-common curl 

ADD . /cproc
WORKDIR /cproc/qbe
RUN make
ENV PATH=/cproc/qbe/obj:$PATH
WORKDIR /cproc
RUN make
