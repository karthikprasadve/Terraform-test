#!/bin/sh
sudo apt update -y
sudo apt install yum -y
sudo apt install apache2 -y
sudo rm -rvf /var/www/html/index.html
touch /var/www/html/index.html
echo "<p>Date/Time: <span id='datetime'></span></p><p><h1>Hello,World!</h1></p><script>var dt = new Date();
document.getElementById('datetime').innerHTML=dt.toLocaleString();</script>" >> /var/www/html/index.html
sudo /etc/init.d/apache2 restart
