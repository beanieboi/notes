deploy:
	bundle exec jekyll build
	rsync -v -crz --delete _site/ ben@wir.abwesend.com:/var/www/com.abwesend.til
