FROM debian:buster

RUN mkdir -p --mode=0755 /etc/apt/keyrings
RUN apt-get update && apt-get -y install sudo apt-transport-https ca-certificates curl
RUN curl -fsSL https://debian.koha-community.org/koha/gpg.asc -o /etc/apt/keyrings/koha.asc
RUN echo 'deb [signed-by=/etc/apt/keyrings/koha.asc] https://debian.koha-community.org/koha 17.11 main' | sudo tee /etc/apt/sources.list.d/koha.list
RUN apt-get update && apt-get -y install koha-common
RUN a2enmod rewrite cgi headers proxy_http
RUN sed -i 's/JSON::Validator::OpenAPI::Mojolicious/JSON::Validator/' /usr/share/perl5/Mojolicious/Plugin/OpenAPI.pm
