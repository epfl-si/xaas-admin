FROM python:3.6

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
RUN pip install --no-cache-dir -r /tmp/local.txt


# Installing MySQL client to be able to import information in DB from a SQL file
RUN apt-get update && apt-get install -y mysql-client && rm -rf /var/lib/apt


COPY ./docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]