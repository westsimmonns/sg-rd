#!/usr/bin/env bash

# 设置各变量
WSPATH=${WSPATH:-'argo'}
UUID=${UUID:-'008c2d95-2bdc-45d0-995f-52a9530daafd'}
WEB_USERNAME=${WEB_USERNAME:-'admin'}
WEB_PASSWORD=${WEB_PASSWORD:-'password'}

generate_config() {
  cat > config.json << EOF
{
    "log":{
        "access":"/dev/null",
        "error":"/dev/null",
        "loglevel":"none"
    },
    "inbounds":[
        {
            "port":8080,
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "flow":"xtls-rprx-vision"
                    }
                ],
                "decryption":"none",
                "fallbacks":[
                    {
                        "dest":3001
                    },
                    {
                        "path":"/${WSPATH}-vmess",
                        "dest":3002
                    }
                ]
            },
            "streamSettings":{
                "network":"tcp"
            }
        },
        {
            "port":3001,
            "listen":"127.0.0.1",
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}"
                    }
                ],
                "decryption":"none"
            },
            "streamSettings":{
                "network":"ws",
                "security":"none"
            }
        },
        {
            "port":3002,
            "listen":"127.0.0.1",
            "protocol":"vmess",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "alterId":0
                    }
                ]
            },
            "streamSettings":{
                "network":"ws",
                "wsSettings":{
                    "path":"/${WSPATH}-vmess"
                }
            },
            "sniffing":{
                "enabled":true,
                "destOverride":[
                    "http",
                    "tls"
                ],
                "metadataOnly":false
            }
        }
    ],
    "dns":{
        "servers":[
            "https+local://8.8.8.8/dns-query"
        ]
    },
    "outbounds":[
        {
            "protocol":"freedom"
        },
        {
            "tag":"WARP",
            "protocol":"wireguard",
            "settings":{
                "secretKey":"YFYOAdbw1bKTHlNNi+aEjBM3BO7unuFC5rOkMRAz9XY=",
                "address":[
                    "172.16.0.2/32",
                    "2606:4700:110:8a36:df92:102a:9602:fa18/128"
                ],
                "peers":[
                    {
                        "publicKey":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                        "allowedIPs":[
                            "0.0.0.0/0",
                            "::/0"
                        ],
                        "endpoint":"162.159.193.10:2408"
                    }
                ],
                "reserved":[78, 135, 76],
                "mtu":1280
            }
        }
    ],
    "routing":{
        "domainStrategy":"AsIs",
        "rules":[
            {
                "type":"field",
                "domain":[
                    "domain:openai.com",
                    "domain:ai.com"
                ],
                "outboundTag":"WARP"
            }
        ]
    }
}
EOF
}

generate_argo() {
  cat > argo.sh << ABC
#!/usr/bin/env bash

argo_type() {
  if [[ -n "\${ARGO_AUTH}" && -n "\${ARGO_DOMAIN}" ]]; then
    [[ \$ARGO_AUTH =~ TunnelSecret ]] && echo \$ARGO_AUTH > tunnel.json && cat > tunnel.yml << EOF
tunnel: \$(cut -d\" -f12 <<< \$ARGO_AUTH)
credentials-file: /app/tunnel.json
protocol: http2

ingress:
  - hostname: \$ARGO_DOMAIN
    service: http://localhost:8080
EOF

    [ -n "\${SSH_DOMAIN}" ] && cat >> tunnel.yml << EOF
  - hostname: \$SSH_DOMAIN
    service: http://localhost:2222
EOF

    cat >> tunnel.yml << EOF
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF

  else
    ARGO_DOMAIN=\$(cat argo.log | grep -o "info.*https://.*trycloudflare.com" | sed "s@.*https://@@g" | tail -n 1)
  fi
}

export_list() {
  VMESS="{ \"v\": \"2\", \"ps\": \"Argo-Vmess\", \"add\": \"icook.hk\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\${ARGO_DOMAIN}\", \"path\": \"/${WSPATH}-vmess?ed=2048\", \"tls\": \"tls\", \"sni\": \"\${ARGO_DOMAIN}\", \"alpn\": \"\" }"

  cat > list << EOF
*******************************************
V2-rayN:
----------------------------
vless://${UUID}@icook.hk:443?encryption=none&security=tls&sni=\${ARGO_DOMAIN}&type=ws&host=\${ARGO_DOMAIN}&path=%2F${WSPATH}-vless?ed=2048#Argo-Vless
----------------------------
vmess://\$(echo \$VMESS | base64 -w0)
*******************************************
EOF
  cat list
}

argo_type
export_list
ABC
}

generate_nezha() {
  cat > nezha.sh << EOF
#!/usr/bin/env bash

# 检测是否已运行
check_run() {
  [[ \$(pgrep -lafx nezha-agent) ]] && echo "哪吒客户端正在运行中" && exit
}

# 若哪吒三个变量不全，则不安装哪吒客户端
check_variable() {
  [[ -z "\${NEZHA_SERVER}" || -z "\${NEZHA_PORT}" || -z "\${NEZHA_KEY}" ]] && exit
}

# 下载最新版本 Nezha Agent
download_agent() {
  if [ ! -e nezha-agent ]; then
    URL=\$(wget -qO- "https://api.github.com/repos/naiba/nezha/releases/latest" | grep -o "https.*linux_amd64.zip")
    URL=\${URL:-https://github.com/naiba/nezha/releases/download/v0.14.11/nezha-agent_linux_amd64.zip}
    wget \${URL}
    unzip -qod ./ nezha-agent_linux_amd64.zip
    rm -f nezha-agent_linux_amd64.zip
  fi
}

check_run
check_variable
download_agent
EOF
}

generate_ttyd() {
  cat > ttyd.sh << EOF
#!/usr/bin/env bash

# 检测是否已运行
check_run() {
  [[ \$(pgrep -lafx ttyd) ]] && echo "ttyd 正在运行中" && exit
}

# 若 ssh argo 域名不设置，则不安装 ttyd
check_variable() {
  [ -z "\${SSH_DOMAIN}" ] && exit
}

# 下载最新版本 ttyd
download_ttyd() {
  if [ ! -e ttyd ]; then
    URL=\$(wget -qO- "https://api.github.com/repos/tsl0922/ttyd/releases/latest" | grep -o "https.*x86_64")
    URL=\${URL:-https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.x86_64}
    wget -O ttyd \${URL}
    chmod +x ttyd
  fi
}

check_run
check_variable
download_ttyd
EOF
}

# 生成 pm2 配置文件
generate_pm2_file() {
  if [[ -n "${ARGO_AUTH}" && -n "${ARGO_DOMAIN}" ]]; then
    [[ $ARGO_AUTH =~ TunnelSecret ]] && ARGO_ARGS="tunnel --edge-ip-version auto --config tunnel.yml run"
    [[ $ARGO_AUTH =~ ^[A-Z0-9a-z=]{120,250}$ ]] && ARGO_ARGS="tunnel --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH}"
  else
    ARGO_ARGS="tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile argo.log --loglevel info --url http://localhost:8080"
  fi

  TLS=${NEZHA_TLS:+'--tls'}

  cat > ecosystem.config.js << EOF
module.exports = {
  "apps":[
      {
          "name":"web",
          "script":"/app/web.js run"
      },
      {
          "name":"argo",
          "script":"cloudflared",
          "args":"${ARGO_ARGS}"
EOF

  [[ -n "${NEZHA_SERVER}" && -n "${NEZHA_PORT}" && -n "${NEZHA_KEY}" ]] && cat >> ecosystem.config.js << EOF
      },
      {
          "name":"nezha",
          "script":"/app/nezha-agent",
          "args":"-s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${TLS}"
EOF
  
  [ -n "${SSH_DOMAIN}" ] && cat >> ecosystem.config.js << EOF
      },
      {
          "name":"ttyd",
          "script":"/app/ttyd",
          "args":"-c ${WEB_USERNAME}:${WEB_PASSWORD} -p 2222 bash"
EOF

  cat >> ecosystem.config.js << EOF
      }
  ]
}
EOF
}

generate_config
generate_argo
generate_nezha
generate_ttyd
generate_pm2_file

[ -e nezha.sh ] && bash nezha.sh
[ -e argo.sh ] && bash argo.sh
[ -e ttyd.sh ] && bash ttyd.sh
[ -e ecosystem.config.js ] && pm2 start
