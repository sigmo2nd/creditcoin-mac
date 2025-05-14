#!/bin/bash
# node_metrics.sh - 크레딧코인 노드 메트릭 HTTP 서버

# 설정
PORT=8080
TOKEN_FILE="$HOME/.node_metrics_token"
TEMP_DIR="/tmp/creditcoin_metrics"
METRICS_FILE="$TEMP_DIR/metrics.json"
HTML_FILE="$TEMP_DIR/index.html"

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 임시 디렉토리 생성
mkdir -p "$TEMP_DIR"

# 토큰 생성 (없는 경우)
if [ ! -f "$TOKEN_FILE" ]; then
  echo -e "${BLUE}API 토큰 생성 중...${NC}"
  openssl rand -hex 16 > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi

# 토큰 읽기
API_TOKEN=$(cat "$TOKEN_FILE")
echo -e "${GREEN}API 토큰: $API_TOKEN${NC}"
echo -e "${YELLOW}이 토큰을 중앙 서버 구성에 추가하세요${NC}"

# 시스템 메트릭 수집 함수
collect_metrics() {
  echo "시스템 메트릭 수집 중..." >&2
  
  # sysinfo.sh가 있으면 그대로 사용
  if command -v sysinfo.sh &> /dev/null; then
    sysinfo.sh -j > "$METRICS_FILE"
    return
  fi
  
  # sysinfo.sh가 없으면 주요 메트릭만 수집
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  # 시스템 정보
  model=$(sysctl hw.model 2>/dev/null | awk -F ": " '{print $2}' || echo "Unknown")
  
  # CPU 정보
  cpu_info=$(top -l 1 -n 0 | grep -E "^CPU")
  user_cpu=$(echo "$cpu_info" | awk '{print $3}' | sed 's/%//')
  sys_cpu=$(echo "$cpu_info" | awk '{print $5}' | sed 's/%//')
  idle_cpu=$(echo "$cpu_info" | awk '{print $7}' | sed 's/%//')
  
  # 메모리 정보
  mem_info=$(vm_stat | grep "Pages")
  page_size=$(vm_stat | grep "page size" | awk '{print $8}')
  
  # 디스크 정보
  disk_info=$(df -h / | grep -v "Filesystem" | head -1)
  disk_total=$(echo "$disk_info" | awk '{print $2}')
  disk_used=$(echo "$disk_info" | awk '{print $3}')
  disk_avail=$(echo "$disk_info" | awk '{print $4}')
  disk_percent=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
  
  # Docker 노드 정보 수집
  if command -v docker &> /dev/null && docker info &> /dev/null; then
    docker_stats=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}" 2>/dev/null | grep -E "node|3node")
    
    # JSON 형식으로 출력
    echo "{" > "$METRICS_FILE"
    echo "  \"timestamp\": \"$timestamp\"," >> "$METRICS_FILE"
    echo "  \"system\": {" >> "$METRICS_FILE"
    echo "    \"model\": \"$model\"," >> "$METRICS_FILE"
    echo "    \"cpu_usage\": {" >> "$METRICS_FILE"
    echo "      \"user\": $user_cpu," >> "$METRICS_FILE"
    echo "      \"system\": $sys_cpu," >> "$METRICS_FILE"
    echo "      \"idle\": $idle_cpu" >> "$METRICS_FILE"
    echo "    }," >> "$METRICS_FILE"
    echo "    \"disk\": {" >> "$METRICS_FILE"
    echo "      \"total\": \"$disk_total\"," >> "$METRICS_FILE"
    echo "      \"used\": \"$disk_used\"," >> "$METRICS_FILE"
    echo "      \"available\": \"$disk_avail\"," >> "$METRICS_FILE"
    echo "      \"percent\": $disk_percent" >> "$METRICS_FILE"
    echo "    }" >> "$METRICS_FILE"
    echo "  }," >> "$METRICS_FILE"
    
    # 노드 정보 추가
    echo "  \"nodes\": [" >> "$METRICS_FILE"
    
    # 노드 처리
    node_count=0
    while IFS=$'\t' read -r name cpu mem mem_pct net; do
      if [ $node_count -gt 0 ]; then
        echo "    }," >> "$METRICS_FILE"
      fi
      
      # CPU 정보 처리
      cpu_clean=$(echo "$cpu" | sed 's/%//')
      
      # 메모리 정보 처리
      mem_parts=(${mem//\// })
      mem_used=${mem_parts[0]}
      mem_limit=${mem_parts[1]}
      
      # 네트워크 정보 처리
      net_parts=(${net//\// })
      rx=${net_parts[0]}
      tx=${net_parts[1]}
      
      echo "    {" >> "$METRICS_FILE"
      echo "      \"name\": \"$name\"," >> "$METRICS_FILE"
      echo "      \"cpu\": $cpu_clean," >> "$METRICS_FILE"
      echo "      \"mem\": \"$mem\"," >> "$METRICS_FILE"
      echo "      \"mem_pct\": $(echo "$mem_pct" | sed 's/%//')," >> "$METRICS_FILE"
      echo "      \"net_rx\": \"$rx\"," >> "$METRICS_FILE"
      echo "      \"net_tx\": \"$tx\"" >> "$METRICS_FILE"
      
      node_count=$((node_count + 1))
    done <<< "$docker_stats"
    
    if [ $node_count -gt 0 ]; then
      echo "    }" >> "$METRICS_FILE"
    fi
    
    echo "  ]" >> "$METRICS_FILE"
    echo "}" >> "$METRICS_FILE"
  else
    # Docker가 없는 경우
    echo "{" > "$METRICS_FILE"
    echo "  \"timestamp\": \"$timestamp\"," >> "$METRICS_FILE"
    echo "  \"system\": {" >> "$METRICS_FILE"
    echo "    \"model\": \"$model\"," >> "$METRICS_FILE"
    echo "    \"cpu_usage\": {" >> "$METRICS_FILE"
    echo "      \"user\": $user_cpu," >> "$METRICS_FILE"
    echo "      \"system\": $sys_cpu," >> "$METRICS_FILE"
    echo "      \"idle\": $idle_cpu" >> "$METRICS_FILE"
    echo "    }," >> "$METRICS_FILE"
    echo "    \"disk\": {" >> "$METRICS_FILE"
    echo "      \"total\": \"$disk_total\"," >> "$METRICS_FILE"
    echo "      \"used\": \"$disk_used\"," >> "$METRICS_FILE"
    echo "      \"available\": \"$disk_avail\"," >> "$METRICS_FILE"
    echo "      \"percent\": $disk_percent" >> "$METRICS_FILE"
    echo "    }" >> "$METRICS_FILE"
    echo "  }," >> "$METRICS_FILE"
    echo "  \"docker\": {" >> "$METRICS_FILE"
    echo "    \"running\": false," >> "$METRICS_FILE"
    echo "    \"message\": \"Docker가 실행 중이 아니거나 액세스할 수 없습니다.\"" >> "$METRICS_FILE"
    echo "  }" >> "$METRICS_FILE"
    echo "}" >> "$METRICS_FILE"
  fi
  
  echo "메트릭 수집 완료" >&2
}

# HTML 파일 생성 (Python 바이트 리터럴 문제 해결)
cat > "$HTML_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Creditcoin Node Metrics</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .info { background: #f8f9fa; padding: 15px; border-radius: 5px; }
        code { background: #eee; padding: 2px 5px; border-radius: 3px; }
    </style>
</head>
<body>
    <h1>Creditcoin Node Metrics Server</h1>
    <div class='info'>
        <p>API 엔드포인트: <code>/metrics</code></p>
        <p>인증 헤더: <code>Authorization: Bearer YOUR_TOKEN</code></p>
        <p>또는 쿼리 파라미터: <code>/metrics?token=YOUR_TOKEN</code></p>
    </div>
</body>
</html>
EOF

# 시작 안내
echo -e "${BLUE}크레딧코인 노드 메트릭 HTTP 서버 시작 중...${NC}"
echo -e "${YELLOW}포트: $PORT${NC}"

# 메트릭 첫 수집
collect_metrics

# Python으로 HTTP 서버 시작 (수정된 코드)
python3 -c "
import http.server
import socketserver
import os
import json
import time
import threading

PORT = $PORT
TOKEN = '$API_TOKEN'
METRICS_FILE = '$METRICS_FILE'
HTML_FILE = '$HTML_FILE'

class MetricsHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # 토큰 검증
        auth_header = self.headers.get('Authorization', '')
        url_token = ''
        
        if '?token=' in self.path:
            url_token = self.path.split('?token=')[1].split('&')[0]
        
        is_authorized = False
        if auth_header.startswith('Bearer ') and auth_header[7:] == TOKEN:
            is_authorized = True
        elif url_token == TOKEN:
            is_authorized = True
        
        # 루트 경로
        if self.path == '/' or self.path.startswith('/?'):
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            
            # HTML 파일을 읽어서 응답
            with open(HTML_FILE, 'rb') as f:
                self.wfile.write(f.read())
            
        # 메트릭 엔드포인트
        elif self.path.startswith('/metrics'):
            if not is_authorized:
                self.send_response(401)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': 'Unauthorized'}).encode())
                return
                
            try:
                with open(METRICS_FILE, 'r') as f:
                    metrics_data = f.read()
                    
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(metrics_data.encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'error': str(e)}).encode())
        
        # 그 외 경로는 404
        else:
            self.send_response(404)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': 'Not found'}).encode())
    
    def log_message(self, format, *args):
        # 로그 출력 형식 커스터마이징
        print(f'\\033[34m[{time.asctime()}] {args[0]} {args[1]} {args[2]}\\033[0m')

# 백그라운드에서 주기적으로 메트릭 수집
def collect_metrics_periodically():
    while True:
        os.system('$TEMP_DIR/metrics_collector.sh')
        time.sleep(10)  # 10초마다 갱신

# 메트릭 수집 스크립트 생성
with open('$TEMP_DIR/metrics_collector.sh', 'w') as f:
    f.write('#!/bin/bash\\n')
    f.write('cd \"$(dirname \"$0\")\"\\n')
    f.write('source \"$0\"\\n')
    f.write('collect_metrics\\n')

os.chmod('$TEMP_DIR/metrics_collector.sh', 0o755)

# 메트릭 수집 쓰레드 시작
collector_thread = threading.Thread(target=collect_metrics_periodically)
collector_thread.daemon = True
collector_thread.start()

# HTTP 서버 시작
with socketserver.TCPServer(('0.0.0.0', PORT), MetricsHandler) as httpd:
    print(f'\\033[32m서버가 http://0.0.0.0:{PORT}에서 시작되었습니다\\033[0m')
    print(f'\\033[33m메트릭 엔드포인트: http://0.0.0.0:{PORT}/metrics\\033[0m')
    print(f'\\033[33m인증 토큰: {TOKEN}\\033[0m')
    httpd.serve_forever()
"