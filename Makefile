deploy:
	bundle exec jekyll build
	rsync -v -crz --delete _site/ wir-wp:/tmp/_site_temp
	ssh wir-wp 'sudo -u www-data rsync -v -crz --delete /tmp/_site_temp/ /var/www/com.abwesend.notes && sudo rm -rf /tmp/_site_temp'
