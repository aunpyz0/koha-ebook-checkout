FROM registry.aunp.xyz/koha:17.11

RUN apt-get -y install mariadb-server supervisor
RUN service mysql start && koha-create --create-db mylibrary
RUN sed -i '/Listen 80/a Listen 81' /etc/apache2/ports.conf
RUN sed -i '/# Intranet/{n;s/80/81/}' /etc/apache2/sites-available/mylibrary.conf
RUN a2dissite 000-default && a2ensite mylibrary

EXPOSE 80
EXPOSE 81
EXPOSE 3306

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

CMD ["/usr/bin/supervisord"]
