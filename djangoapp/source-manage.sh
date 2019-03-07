#!/bin/bash
# This script will make application files be used from an external volume ($USE_EXTERNAL_APP_SOURCE=1) or
# from inside the container. Files have already have been copied in $TMP_APP_SOURCE_FILES and if we have to use
# them for application, we will just move them at the right place.

USE_EXTERNAL_APP_SOURCE=$1
TMP_APP_SOURCE_FILES=$2

# If we have to use external source files for app,
if [ "${USE_EXTERNAL_APP_SOURCE}" = "1" ]
then
    echo "Using external source for app, deleting what was copied..."
    rm -rf ${TMP_APP_SOURCE_FILES}
else
    echo "Using internal source for app, moving to correct place..."
    mv -f ${TMP_APP_SOURCE_FILES} /usr/src/
fi