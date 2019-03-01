FROM python:3.6

MAINTAINER Lucien Chaboudez <lucien.chaboudez@epfl.ch>

EXPOSE 80

WORKDIR /usr/src/xaas-admin

# Last argument is target for copy (located in WORKDIR). Other ones are files/dirs to copy
COPY prepare_db.sh xaas-admin/ ./

COPY ./requirements /tmp

RUN pip install --no-cache-dir -r /tmp/local.txt

CMD ["python", "manage.py", "runserver", "0.0.0.0:80"]