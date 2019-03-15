FROM python:3.6

ARG DJANGO_SETTINGS_MODULE


EXPOSE 80

WORKDIR /usr/src/xaas-admin


# Handling source location depending on DJANGO_SETTINGS_MODULE env var which tells Django in which environment it will
# be executed. If it will run "locally" (config.settings.local), source will be outside container (for easier development)
# Otherwise, it will be inside container.
COPY ./xaas-admin /tmp/xaas-admin

# We have to add write rights to files because in OpenShift, it won't be "root" user that will be used to execute
# docker-entrypoint.sh script, it will be another user so we have to ensure that he will have enough rights.
RUN chmod -R a+w /usr/src/xaas-admin
RUN chmod -R 777 /tmp

# Python requirements
COPY ./requirements /tmp

# Running installation script. We use an exteral script to be able to use DJANGO_SETTINGS_MODULE parameter
COPY ./install.sh /tmp
RUN /tmp/install.sh

# Installing MySQL client to be able to import information in DB from a SQL file
RUN apt-get update && apt-get install -y mysql-client && rm -rf /var/lib/apt


# Entrypoint
COPY ./docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
