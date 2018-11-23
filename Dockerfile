FROM debian:9
SHELL ["/bin/bash", "-exo", "pipefail", "-c"]

RUN apt-get update ;\
	DEBIAN_FRONTEND=noninteractive apt-get install --no-install-{recommends,suggests} -y \
		apt-transport-https gnupg2 dirmngr ca-certificates ;\
	apt-get clean ;\
	rm -vrf /var/lib/apt/lists/* ;\
	apt-key adv --fetch-keys 'https://packages.icinga.com/icinga.key' ;\
	DEBIAN_FRONTEND=noninteractive apt-get purge -y apt-transport-https gnupg2 dirmngr ca-certificates ;\
	DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y

ADD apt-icinga.list /etc/apt/sources.list.d/icinga.list

RUN apt-get update ;\
	DEBIAN_FRONTEND=noninteractive apt-get install --no-install-{recommends,suggests} -y \
		apache2 icingaweb2{,-module-monitoring} php7.0-{intl,imagick,mysql} locales \
		mariadb-server dbconfig-no-thanks ;\
	apt-get clean ;\
	rm -vrf /var/lib/apt/lists/* /etc/icingaweb2/* ;\
	a2dissite 000-default ;\
	perl -pi -e 'if (!%locales) { %locales = (); for my $d ("", "/modules/monitoring") { for my $f (glob "/usr/share/icingaweb2${d}/application/locale/*_*") { if ($f =~ m~/(\w+)$~) { $locales{$1} = undef } } } } s/^# ?// if (/ UTF-8$/ && /^# (\w+)/ && exists $locales{$1})' /etc/locale.gen

RUN apt-get update ;\
	DEBIAN_FRONTEND=noninteractive apt-get install --no-install-{recommends,suggests} -y \
		icinga2-{bin,ido-mysql} ;\
	apt-get clean ;\
	rm -vrf /var/lib/apt/lists/*

COPY icinga2-bin_2.10.2-1_amd64.deb icinga2-common_2.10.2-1_all.deb icinga2-ido-mysql_2.10.2-1_amd64.deb /

RUN DEBIAN_FRONTEND=noninteractive dpkg -i /icinga2*.deb ;\
	rm -vrf /etc/icinga2/conf.d/* ;\
	/usr/lib/icinga2/prepare-dirs /etc/default/icinga2 ;\
	icinga2 feature disable notification ;\
	icinga2 feature enable command

COPY icinga2/ido.conf /etc/icinga2/features-available/ido-mysql.conf
COPY icinga2/zones.conf /etc/icinga2/zones.conf

RUN icinga2 feature enable ido-mysql

COPY --from=ochinchina/supervisord:latest /usr/local/bin/supervisord /usr/local/bin/

RUN icinga2 pki new-ca ;\
	install -m 0750 -o nagios -g nagios -d /var/lib/icinga2/certs ;\
	ln -vs /var/lib/icinga2/{ca,certs}/ca.crt ;\
	for n in {master,sat-{a,b}}-{1,2}; do \
		icinga2 pki new-cert --cn $n --key /var/lib/icinga2/certs/$n.key --csr /var/lib/icinga2/certs/$n.csr ;\
		icinga2 pki sign-csr --csr /var/lib/icinga2/certs/$n.csr --cert /var/lib/icinga2/certs/$n.crt ;\
	done

RUN mkfifo /var/log/icinga2/icinga2.log ;\
	chown nagios:nagios /var/log/icinga2/icinga2.log

RUN install -m 755 -o mysql -g root -d /var/run/mysqld ;\
	mysqld -u mysql & \
	MYSQLD_PID="$!" ;\
	while ! mysql <<<''; do sleep 1; done ;\
	mysql <<<"CREATE DATABASE icinga2; USE icinga2; $(< /usr/share/icinga2-ido-mysql/schema/mysql.sql) GRANT ALL ON icinga2.* TO nagios@localhost IDENTIFIED VIA unix_socket; GRANT SELECT ON icinga2.* TO 'www-data'@localhost IDENTIFIED VIA unix_socket;" ;\
	kill "$MYSQLD_PID" ;\
	while test -e "/proc/$MYSQLD_PID"; do sleep 1; done

COPY php-icingaweb2.ini /etc/php/7.0/apache2/conf.d/99-icingaweb2.ini
ADD --chown=www-data:icingaweb2 icingaweb2 /etc/icingaweb2

RUN install -o www-data -g icingaweb2 -m 02770 -d /etc/icingaweb2/enabledModules ;\
	ln -vs /usr/share/icingaweb2/modules/monitoring /etc/icingaweb2/enabledModules/monitoring ;\
	locale-gen -j 4

COPY apache2-site.conf /etc/apache2/sites-available/iw2.conf
RUN a2ensite iw2

COPY run-icinga2.sh /
COPY supervisord.conf /etc/
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisord.conf"]
