FROM alpine/k8s:1.28.2
RUN apk --no-cache add hey bc py-pip gcc python3-dev musl-dev linux-headers

RUN pip install locust

WORKDIR /app

COPY ../scripts/test_celery_flow.sh .
RUN chmod +x test_celery_flow.sh

ENTRYPOINT ["/bin/sh"]
