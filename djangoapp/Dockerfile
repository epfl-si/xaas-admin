FROM python:3.6

ARG DJANGO_SETTINGS_MODULE

ENV TMP_APP_SOURCE_FILES=/tmp/xaas-admin

EXPOSE 80

WORKDIR /usr/src/xaas-admin


# Handling source location depending on DJANGO_SETTINGS_MODULE env var which tells Django in which environment it will
# be executed. If it will run "locally" (config.settings.local), source will be outside container (for easier development)
# Otherwise, it will be inside container.
COPY ./xaas-admin ${TMP_APP_SOURCE_FILES}

# Python requirements for pip install
COPY ./requirements /tmp

# Running installation script. We use an exteral script to be able to use DJANGO_SETTINGS_MODULE parameter
COPY ./build.sh /tmp
RUN /tmp/build.sh

# Installing MySQL client to be able to import information in DB from a SQL file
RUN apt-get update && apt-get install -y mysql-client && rm -rf /var/lib/apt


# Entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
