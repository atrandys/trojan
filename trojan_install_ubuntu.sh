#!/bin/bash

function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}

systemctl stop ufw
systemctl disable ufw

sudo add-apt-repository -y ppa:greaterfire/trojan
sudo apt-get -y update
sudo apt-get -y install unzip wget trojan

sudo apt-get -y install nginx
mkdir /etc/nginx/ssl

green "======================"
green " 输入解析到此VPS的域名"
green "======================"
read domain

cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen       80;
    server_name  $domain;
    root /usr/share/nginx/html;
    index index.php index.html index.htm;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
EOF

systemctl start nginx.service

curl https://get.acme.sh | sh
~/.acme.sh/acme.sh  --issue  -d $domain  --webroot /usr/share/nginx/html/

~/.acme.sh/acme.sh  --installcert  -d  $domain   \
        --key-file   /etc/nginx/ssl/$domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "service nginx force-reload"

cd /etc/trojan/
rm -f /etc/trojan/config.json

cat > /etc/trojan/server.conf <<-EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "password1"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/etc/nginx/ssl/fullchain.cer",
        "key": "/etc/nginx/ssl/$domain.key",
        "key_password": "",
        "cipher": "TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5",
        "prefer_server_cipher": true,
        "alpn": [
            "h2",
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": ""
    }
}
EOF

mypassword=$(cat /dev/urandom | head -1 | md5sum | head -c 4)
sed -i "s/password1/$mypassword/" /etc/trojan/server.conf

rm -f /usr/share/nginx/html/*
cd /usr/share/nginx/html
wget https://github.com/atrandys/v2ray-ws-tls/raw/master/web.zip
unzip web.zip
systemctl restart nginx.service
systemctl enable nginx.service
cat > /etc/systemd/system/trojan.service <<-EOF
[Unit]
Description=trojan
After=syslog.target network.target remote-fs.target nss-lookup.target
 
[Service]
Type=forking
ExecStart=/usr/bin/trojan -c /etc/trojan/server.conf
Restart=always
 
[Install]
WantedBy=multi-user.target
EOF
systemctl start trojan.service
systemctl enable trojan.service

green "===============安装OK==============="
green " 密码：$mypassword"
green " 证书：/etc/nginx/ssl/fullchain.cer"
