ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

COPY kubernetes/postgres/config/postgresql.conf /etc/postgresql/postgresql.conf
COPY kubernetes/postgres/config/pg_hba.conf      /etc/postgresql/pg_hba.conf
RUN chown postgres:postgres /etc/postgresql/postgresql.conf /etc/postgresql/pg_hba.conf

CMD ["postgres","-c","config_file=/etc/postgresql/postgresql.conf","-c","hba_file=/etc/postgresql/pg_hba.conf"]
