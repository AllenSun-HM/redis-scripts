#!/bin/bash

BASE_DIR=/usr/local/redis-cluster

PORTS=`seq 7000 7005`

START_UP=$BASE_DIR/startup.sh

SERVICE=redis-cluster.service

# Remove redis cluster
function remove_cluster() {
  # kill redis servers
  ps -ef | grep redis-server | grep cluster | awk '{print $2}' | xargs kill -9
  # disable systemd
  systemctl disable redis-cluster.service
  # rm cluster data
  if [ -d $BASE_DIR ]; then
    rm -rf $BASE_DIR
  fi
}

if [ "$1" = "--remove" ]; then
  remove_cluster
  exit 0
fi

# Check redis command
if [ ! -f "/usr/local/bin/redis-server" ]; then
  echo "Redis not ready, please install redis firstly!"
  echo ""
  echo "===== Install redis as follows ====="
  wget http://download.redis.io/releases/redis-stable.tar.gz -P /usr/local/src
  cd /usr/local/src/
  tar -zxvf redis-5.0.7.tar.gz
  cd redis-5.0.7
  install GCC if not exists
  yum install -y gcc-c++
  make MALLOC=libc install

  echo ""
fi

# User custom setting
echo -n "Enter your host's public address(default 127.0.0.1):"
read cluster_address


# enter work directory
mkdir -p $BASE_DIR
cd $BASE_DIR

# generate configuration files
function generate_instance_conf() {
  echo "configuring server $1"

  # clean conf file
  echo "" > $1/redis.conf
  # write conf
  echo "port $1" >> $1/redis.conf
  echo "bind 0.0.0.0" >> $1/redis.conf
  echo "dir $BASE_DIR/$port/data" >> $1/redis.conf
  echo "cluster-enabled yes" >> $1/redis.conf
  echo "cluster-config-file nodes-$1.conf" >> $1/redis.conf
  echo "cluster-node-timeout 5000" >> $1/redis.conf
  if [ -n "$cluster_address" ]; then
    echo "cluster-announce-ip $cluster_address" >> $1/redis.conf
  else
    echo "cluster-announce-ip 127.0.0.1" >> $1/redis.conf
  fi
  echo "appendonly yes" >> $1/redis.conf
  echo "daemonize yes" >> $1/redis.conf
}


# mkdir dirs and setup startup.sh
echo "#!/bin/bash" > $START_UP
servers=
for port in $PORTS; do
  mkdir -p $BASE_DIR/$port/data
  # generate conf files
  generate_instance_conf $port
  #
  echo "/usr/local/bin/redis-server $BASE_DIR/$port/redis.conf" >> $START_UP
  # servers
  servers="$servers 127.0.0.1:$port "
done



# startup instances
chmod +x $START_UP
echo "starting servers..."
$START_UP
sleep 5s
echo "servers ready!"

# create cluster
echo "configuring cluster..."
/usr/local/bin/redis-cli --cluster create $servers --cluster-replicas 1
echo "configured!"

# generate redis-cluster service file
cat << EOT > $BASE_DIR/redis-cluster.service
[Unit]
Description=Redis 5.0 Cluster Service
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/redis-cluster/startup.sh

[Install]
WantedBy=default.target
EOT

# create service
echo "Creating redis cluster service..."
ln -s $BASE_DIR/$SERVICE /etc/systemd/system/$SERVICE
sudo systemctl daemon-reload && sudo systemctl enable $SERVICE && sudo systemctl start $SERVICE

# Cluster OK
echo ""
echo "Completed!"
echo ""
echo "Test cluster with: /usr/local/bin/redis-cli -c -h 127.0.0.1 -p 7000"
echo ""
echo "127.0.0.1:7000>cluster nodes"
