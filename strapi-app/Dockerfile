FROM node:11.1.0-alpine

USER root

WORKDIR /usr/src/api

RUN echo "unsafe-perm = true" >> ~/.npmrc

# Installing Strapi
RUN npm install -g strapi@3.0.0-beta.18

# Moving the start-up script to the appropriate location
COPY strapi.sh /root

# Giving read and execution permissions
RUN chmod +x /root/strapi.sh

WORKDIR /etc/init.d/

EXPOSE 1337

ENTRYPOINT [ "/root/strapi.sh" ]