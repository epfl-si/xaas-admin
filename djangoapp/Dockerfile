FROM python:3.6

ARG USE_EXTERNAL_APP_SOURCE=0
ENV TMP_APP_SOURCE_FILES="/tmp/xaas-admin"

EXPOSE 80

WORKDIR /usr/src/xaas-admin


# Handling source location depending on $USE_EXTERNAL_APP_SOURCE argument. Source can be inside container (for production)
# or outside (for development)
COPY ./source-manage.sh /tmp/
COPY ./xaas-admin ${TMP_APP_SOURCE_FILES}
RUN /tmp/source-manage.sh ${USE_EXTERNAL_APP_SOURCE} ${TMP_APP_SOURCE_FILES}


# Python requirements
COPY ./requirements /tmp
RUN pip install --no-cache-dir -r /tmp/local.txt


# Installing MySQL client to be able to import information in DB from a SQL file
RUN apt-get update && apt-get install -y mysql-client && rm -rf /var/lib/apt


COPY ./docker-entrypoint.sh /tmp/docker-entrypoint.sh
ENTRYPOINT ["/tmp/docker-entrypoint.sh"]