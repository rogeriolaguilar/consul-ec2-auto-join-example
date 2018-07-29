#!/usr/bin/env bash
locale-gen pt_BR.UTF-8
timedatectl set-timezone America/Sao_Paulo

echo "########################### Installing dependencies ###########################"
apt -yqq update
apt -yqq install unzip apt-transport-https ca-certificates software-properties-common


echo "########################### Installing DOCKER  ###########################"
apt -y remove docker docker-engine docker.io
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"
apt -y update
apt -y install docker-ce
usermod -aG docker ubuntu


echo "########################### Grabbing IPs...     ###########################"
PRIVATE_IP=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)


echo "########################### Installing Consul... ###########################"
curl https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip -o /tmp/consul.zip  \
  && unzip /tmp/consul.zip -d /usr/local/bin/ \
  && chmod +x /usr/local/bin/consul \
  && rm -rf /tmp/consul.zip

mkdir -p ${consul_home}/data
cat > ${consul_home}/config.json << EOF
{
  "bind_addr": "$PRIVATE_IP",
  "advertise_addr": "$PRIVATE_IP",
  "advertise_addr_wan": "$PUBLIC_IP",
  "data_dir": "${consul_home}/data",
  "disable_remote_exec": true,
  "disable_update_check": true,
  "leave_on_terminate": true,
  ${config}
}
EOF

cat > /usr/local/bin/consul_agent_service.sh << 'EOF' 
#!/bin/bash -x
function start_service {
  /usr/local/bin/consul agent -config-dir ${consul_home}/config.json  >> ${consul_home}/consul.log 2>&1
}

function stop_service {
  PID=$( ps ax | grep "consul agent" | grep -v grep | cut -d " " -f 2 )
  kill $PID
}

function main {
  case $1 in
    "start" )
      start_service ;;
    "stop" )
      stop_service ;;
    "restart" )
      stop_service && start_service ;;
  esac
}
main $1;
EOF
chmod +x /usr/local/bin/consul_agent_service.sh

mkdir -p  /usr/lib/systemd/system/
cat <<EOF > /usr/lib/systemd/system/consul-agent.service
[Unit]
Description=consul-agent
After=network.service

[Service]
ExecStart=/usr/local/bin/consul_agent_service.sh start
ExecStop=/usr/local/bin/consul_agent_service.sh stop

# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF


echo "########################### Installing NOMAD... ###########################"
curl https://releases.hashicorp.com/nomad/0.8.1/nomad_0.8.1_linux_amd64.zip \
  -o /tmp/nomad_0.8.1_linux_amd64.zip \
  && unzip /tmp/nomad_0.8.1_linux_amd64.zip -d /usr/local/bin/ \
  && rm -rf /tmp/nomad_0.8.1_linux_amd64.zip

cat > /usr/local/bin/nomad_server_service.sh << 'EOF' 
#!/bin/bash
function start_service {
  /usr/local/bin/nomad agent \
    -server \
    -data-dir='/data/nomad_server' \
    -bootstrap-expect=3 \
    -node=$HOSTNAME:4648 \
    >> '/var/log/nomad_server.log' 2>&1
}

function stop_service {
  PID=$(ps ax | grep "nomad agent -server" | grep -v grep | cut -d " " -f 2)
  kill $PID
}

function main {
  case ${1} in
    "start" )
      start_service ;;
    "stop" )
      stop_service ;;
    "restart" )
      stop_service && start_service ;;
  esac
}
main ${1};
EOF
chmod +x /usr/local/bin/nomad_server_service.sh

mkdir -p  /usr/lib/systemd/system/
cat <<EOF > /usr/lib/systemd/system/nomad-server.service
[Unit]
Description=nomad-server
After=consul-agent.service
[Service]
ExecStart=/usr/local/bin/nomad_server_service.sh start
ExecStop=/usr/local/bin/nomad_server_service.sh stop

# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF


echo "########################### Starting agents... ###########################"
systemctl daemon-reload \
  && systemctl start consul-agent \
  && systemctl enable consul-agent
  && systemctl start nomad-server \
  && systemctl enable nomad-server

reboot