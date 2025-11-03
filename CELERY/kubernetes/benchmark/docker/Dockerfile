FROM alpine/k8s:1.28.2
RUN apk --no-cache add hey bc py-pip gcc python3-dev musl-dev linux-headers

RUN pip install locust

WORKDIR /app

COPY ../scripts/benchmark.sh .
COPY ../scripts/locustfile.py .
RUN chmod +x benchmark.sh

ENTRYPOINT ["/bin/sh"]