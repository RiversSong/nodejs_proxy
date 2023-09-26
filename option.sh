#!/bin/bash
NEZHA_SERVER=${NEZHA_SERVER:-''}               #哪吒面板地址
NEZHA_PORT=${NEZHA_PORT:-'5555'}                         #哪吒面板端口
NEZHA_KEY=${NEZHA_KEY:-''}             #哪吒面板密钥
NEZHA_TLS=${NEZHA_TLS:-''}                               #哪吒面板是否开启tls，留空即为不开启
ARGO_DOMAIN=${ARGO_DOMAIN:-''}           #ARGO隧道域名，留空为启用临时隧道
ARGO_AUTH=${ARGO_AUTH:-''}      
WSPATH=${WSPATH:-'argo'}

UUID="d342d11e-d424-4583-b36e-524ab1f0afa4"
PORT=80
# 读取base.conf文件中的值

cuuid=`awk -F '=' '/\[base\]/{a=1}a==1&&$1~/uuid/{print $2;exit}' ./base.conf`
if [ -n "$cuuid" ]; then
    UUID=${cuuid}
	echo "${UUID}"
fi

cport=`awk -F '=' '/\[base\]/{a=1}a==1&&$1~/port/{print $2;exit}' ./base.conf`
if [ -n "$cport" ]; then
    PORT=${cport}
	echo "${PORT}"
fi

cNEZHA_SERVER=`awk -F '=' '/\[base\]/{a=1}a==1&&$1~/nezhaserver/{print $2;exit}' ./base.conf`
if [ -n "$cNEZHA_SERVER" ]; then
    NEZHA_SERVER=${cNEZHA_SERVER}
	echo "${NEZHA_SERVER}"
fi

cNEZHA_PORT=`awk -F '=' '/\[base\]/{a=1}a==1&&$1~/nezhaport/{print $2;exit}' ./base.conf`
if [ -n "$cNEZHA_PORT" ]; then
    NEZHA_PORT=${cNEZHA_PORT}
	echo "${NEZHA_PORT}"
fi

cNEZHA_KEY=`awk -F '=' '/\[base\]/{a=1}a==1&&$1~/nezhakey/{print $2;exit}' ./base.conf`
if [ -n "$cNEZHA_KEY" ]; then
    NEZHA_KEY=${cNEZHA_KEY}
	echo "${NEZHA_KEY}"
fi

cARGO_DOMAIN=`awk -F '=' '/\[base\]/{a=1}a==1&&$1~/argodomain/{print $2;exit}' ./base.conf`
if [ -n "$cARGO_DOMAIN" ]; then
    ARGO_DOMAIN="${cARGO_DOMAIN}"
	echo "${ARGO_DOMAIN}"
fi

cARGO_AUTH=$(grep -oP 'argoauth\s*=\s*\K.*' base.conf | cut -d' ' -f1)
if [ -n "$cARGO_AUTH" ]; then
    ARGO_AUTH="${cARGO_AUTH}"
	echo "${ARGO_AUTH}"
fi

set_download_url() {
  local program_name="$1"
  local default_url="$2"
  local x64_url="$3"

  if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "amd64" ] || [ "$(uname -m)" = "x64" ]; then
    download_url="$x64_url"
  else
    download_url="$default_url"
  fi
}

download_program() {
  local program_name="$1"
  local default_url="$2"
  local x64_url="$3"

  set_download_url "$program_name" "$default_url" "$x64_url"

  if [ ! -f "$program_name" ]; then
    if [ -n "$download_url" ]; then
      echo "Downloading $program_name..."
      curl -sSL "$download_url" -o "$program_name"
      dd if=/dev/urandom bs=1024 count=1024 | base64 >> "$program_name"
      echo "Downloaded $program_name"
    else
      echo "Skipping download for $program_name"
    fi
  else
    dd if=/dev/urandom bs=1024 count=1024 | base64 >> "$program_name"
    echo "$program_name already exists, skipping download"
  fi
}


download_program "server" "https://github.com/fscarmen2/X-for-Botshard-ARM/raw/main/nezha-agent" "https://github.com/fscarmen2/X-for-Stozu/raw/main/nezha-agent"
sleep 6

download_program "discord" "https://github.com/cloudflare/cloudflared/releases/download/2023.8.0/cloudflared-linux-arm64" "https://github.com/cloudflare/cloudflared/releases/download/2023.8.0/cloudflared-linux-amd64"
sleep 6

cleanup_files() {
  rm -rf boot.log list.txt 
}

argo_type() {
  if [[ -z $ARGO_AUTH || -z $ARGO_DOMAIN ]]; then
    echo "ARGO_AUTH or ARGO_DOMAIN is empty,Useing Quick Tunnels"
    return
  fi

  if [[ $ARGO_AUTH =~ TunnelSecret ]]; then
    echo $ARGO_AUTH > tunnel.json
    cat > tunnel.yml << EOF
tunnel: $(cut -d\" -f12 <<< $ARGO_AUTH)
credentials-file: ./tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:${PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
  else
    echo "ARGO_AUTH no't TunnelSecret"
  fi
}


run() {
  if [ -e server ]; then
    chmod +x server
    if [ -n "$NEZHA_SERVER" ] && [ -n "$NEZHA_PORT" ] && [ -n "$NEZHA_KEY" ]; then
    nohup ./server -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 &
    keep1="nohup ./server -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS} >/dev/null 2>&1 &"
    fi
  fi

  if [ -e discord ]; then
    chmod +x discord
if [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
  args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info run --token ${ARGO_AUTH}"
elif [[ $ARGO_AUTH =~ TunnelSecret ]]; then
  args="tunnel --edge-ip-version auto --config tunnel.yml run"
else
  args="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile boot.log --loglevel info --url http://localhost:${PORT}"
fi
nohup ./discord $args >/dev/null 2>&1 &
keep2="nohup ./discord $args >/dev/null 2>&1 &"
  fi
} 


cleanup_files
sleep 2
argo_type
sleep 3
run
sleep 15

function get_argo_domain() {
  if [[ -n $ARGO_AUTH ]]; then
    echo "$ARGO_DOMAIN"
  else
    cat boot.log | grep trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}'
  fi
}

isp=$(curl -s https://speed.cloudflare.com/meta | awk -F\" '{print $26"-"$18"-"$30}' | sed -e 's/ /_/g')
sleep 3

generate_links() {
  argo=$(get_argo_domain)
  sleep 1

  cat > list.txt <<EOF
*******************************************
skk.moe 可替换为CF优选IP,端口 443 可改为 2053 2083 2087 2096 8443
----------------------------
vless://${UUID}@skk.moe:443?encryption=none&security=tls&sni=${argo}&type=ws&host=${argo}&path=%2Fladder#${isp}-Vl
----------------------------
由于该软件导出的链接不全，请自行处理如下: 传输协议: WS ， 伪装域名: ${argo} ，路径: /ladder ， 传输层安全: tls ， sni: ${argo}
*******************************************
vless://${UUID}@skk.moe:443?encryption=none&security=tls&type=ws&host=${argo}&path=/ladder&sni=${argo}#${isp}-Vl
*******************************************
EOF

# # base64 -w0 encode.txt > sub.txt 

  cat list.txt
  echo -e "\Saveing list.txt"
}

generate_links

if [ -n "$STARTUP" ]; then
  if [[ "$STARTUP" == *"java"* ]]; then
    java -Xms128M -XX:MaxRAMPercentage=95.0 -Dterminal.jline=false -Dterminal.ansi=true -jar server.jar
  elif [[ "$STARTUP" == *"bedrock_server"* ]]; then
    ./bedrock_server1
  fi
fi


function start_server_program() {
if [ -n "$keep1" ]; then
  if [ -z "$pid" ]; then
    echo "程序'$program'未运行，正在启动..."
    eval "$command"
  else
    echo "程序'$program'正在运行，PID: $pid"
  fi
else
  echo "程序'$program'不需要启动，无需执行任何命令"
fi
}

function start_discord_program() {
  if [ -z "$pid" ]; then
    echo "程序'$program'未运行，正在启动..."
    cleanup_files
    sleep 2
    eval "$command"
    sleep 5
    generate_links
    sleep 3
  else
    echo "程序'$program'正在运行，PID: $pid"
  fi
}

function start_program() {
  local program=$1
  local command=$2

  pid=$(pidof "$program")

  if [ "$program" = "server" ]; then
    start_server_program
  elif [ "$program" = "discord" ]; then
    start_discord_program
  fi
}

programs=("server" "discord")
commands=("$keep1" "$keep2")

while true; do
  for ((i=0; i<${#programs[@]}; i++)); do
    program=${programs[i]}
    command=${commands[i]}

    start_program "$program" "$command"
  done
  sleep 180
done
