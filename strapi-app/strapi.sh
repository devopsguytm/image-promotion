#!/bin/sh

strapiCount=1
count=1
####################START_SERVICES#################################################
while :
do
    sleep 5

    APP_NAME=strapi-example

    DATABASE_CLIENT=postgres
    DATABASE_NAME=strapidb
    DATABASE_HOST=${POSTGRESQL_SERVICE_HOST}
    DATABASE_PORT=${POSTGRESQL_SERVICE_PORT}
    DATABASE_USERNAME=strapi
    DATABASE_PASSWORD=password

    if [ ! -f "/persistent/${APP_NAME}/package.json" ] && [ ${strapiCount} == 1 ]
    then
        echo "====> creating project for strapi <===="
        mkdir -p /persistent/
        cd /persistent/
        strapi new ${APP_NAME} --dbclient=${DATABASE_CLIENT} --dbhost=${DATABASE_HOST} --dbport=${DATABASE_PORT} --dbname=${DATABASE_NAME} --dbusername=${DATABASE_USERNAME}   --dbpassword=${DATABASE_PASSWORD}
        chown -R  /persistent/${APP_NAME}
    elif [ ! -d "/persistent/${APP_NAME}/node_modules" ]
    then
        echo "===> installing node modules in existing strapi project <====="
        npm install --prefix ./$APP_NAME
    fi

    if [ ${strapiCount} == 1 ]
    then
        echo "====> starting strapi <===="
        cd /persistent/${APP_NAME}
        npm run build
        strapi start &
    fi

    strapiCount=`expr $strapiCount + 1`
    cd
    sleep 60
done