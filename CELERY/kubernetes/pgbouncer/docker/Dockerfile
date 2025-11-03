ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

COPY kubernetes/pgbouncer/config/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini
COPY kubernetes/pgbouncer/config/userlist.txt /etc/pgbouncer/userlist.txt

CMD ["pgbouncer", "-u", "postgres", "/etc/pgbouncer/pgbouncer.ini"]
