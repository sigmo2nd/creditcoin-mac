use sysinfo::{System, SystemExt, CpuExt};
use bollard::Docker;
use bollard::container::{ListContainersOptions, StatsOptions};
use std::collections::HashMap;
use std::error::Error;
use std::env;
use tokio::time;
use std::time::Duration;
use futures_util::{SinkExt, StreamExt, TryStreamExt};
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message};
use url::Url;
use serde::{Serialize, Deserialize};
use std::io::{self, Write};
use tokio::sync::mpsc;

// 명령어 처리 모듈 추가
mod client_command_handler;
use client_command_handler::{CommandHandler, CommandMessage, CommandResponse, CommandStatus};

// 환경변수 이름 정의
const ENV_CREDITCOIN_DIR: &str = "CREDITCOIN_DIR";
const ENV_NODE_NAMES: &str = "NODE_NAMES";
const ENV_MONITOR_INTERVAL: &str = "MONITOR_INTERVAL";
const ENV_WS_SERVER_URL: &str = "WS_SERVER_URL";
const ENV_SERVER_ID: &str = "SERVER_ID";

// 기본값 정의
const DEFAULT_CREDITCOIN_DIR: &str = "/Users/sieg/creditcoin-mac";
const DEFAULT_MONITOR_INTERVAL: u64 = 5; // 5초
const DEFAULT_WS_SERVER_URL: &str = "ws://localhost:8080/ws"; // HTTP 사용 (테스트용)
const DEFAULT_SERVER_ID: &str = "server1";

// ANSI 이스케이프 시퀀스
const CLEAR_SCREEN: &str = "\x1B[2J\x1B[1;1H";
const COLOR_RESET: &str = "\x1B[0m";
const COLOR_RED: &str = "\x1B[31m";
const COLOR_GREEN: &str = "\x1B[32m";
const COLOR_YELLOW: &str = "\x1B[33m";
const COLOR_CYAN: &str = "\x1B[36m";
const COLOR_WHITE: &str = "\x1B[37m";
const STYLE_BOLD: &str = "\x1B[1m";

// 서버로 전송할 데이터 구조체
#[derive(Serialize, Deserialize, Debug)]
struct ServerData {
    server_id: String,
    timestamp: u64,
    system: SystemMetricsData,
    containers: Vec<ContainerMetricsData>,
}

// 시스템 메트릭 구조체 (직렬화 가능)
#[derive(Serialize, Deserialize, Debug)]
struct SystemMetricsData {
    host_name: String,
    cpu_model: String,  // 추가된 필드
    cpu_usage: f32,
    cpu_cores: usize,
    memory_total: u64,
    memory_used: u64,
    memory_used_percent: f32,
    swap_total: u64,
    swap_used: u64,
    uptime: u64,
    disk_total: u64,   // 디스크 총량 필드 추가
    disk_used: u64,    // 디스크 사용량 필드 추가
}

// 컨테이너 메트릭 구조체 (직렬화 가능)
#[derive(Serialize, Deserialize, Debug)]
struct ContainerMetricsData {
    name: String,
    id: String,
    status: String,
    cpu_usage: f64,
    memory_usage: u64,
    memory_limit: u64,
    memory_percent: f64,
    network_rx: u64,
    network_tx: u64,
    nickname: Option<String>, // 노드 별명 추가
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    println!("크레딧코인 모니터링 클라이언트 시작");
    
    // 환경변수 로드
    let creditcoin_dir = env::var(ENV_CREDITCOIN_DIR).unwrap_or_else(|_| DEFAULT_CREDITCOIN_DIR.to_string());
    let node_names = env::var(ENV_NODE_NAMES).unwrap_or_else(|_| "node,3node".to_string());
    let node_names: Vec<String> = node_names.split(',').map(|s| s.trim().to_string()).collect();
    let monitor_interval = env::var(ENV_MONITOR_INTERVAL)
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(DEFAULT_MONITOR_INTERVAL);
    let ws_server_url = env::var(ENV_WS_SERVER_URL).unwrap_or_else(|_| DEFAULT_WS_SERVER_URL.to_string());
    let server_id = env::var(ENV_SERVER_ID).unwrap_or_else(|_| DEFAULT_SERVER_ID.to_string());
    
    println!("초기화 정보:");
    println!("- CREDITCOIN_DIR: {}", creditcoin_dir);
    println!("- 모니터링 대상 노드: {:?}", node_names);
    println!("- 모니터링 간격: {}초", monitor_interval);
    println!("- 웹소켓 서버 URL: {}", ws_server_url);
    println!("- 서버 ID: {}", server_id);
    println!("잠시 후 모니터링이 시작됩니다...");
    time::sleep(Duration::from_secs(2)).await;
    
    // 웹소켓 서버 연결
    let url = Url::parse(&ws_server_url)?;
    
    // 자체 서명 인증서 허용 설정 (개발 환경용)
    println!("SSL 인증서 검증을 건너뜁니다 (개발 환경)...");
    std::env::set_var("RUSTLS_DANGEROUS_DISABLE_CERTIFICATE_VERIFICATION", "1");
    
    match handle_websocket(url, server_id, node_names.clone()).await {
        Ok(_) => println!("웹소켓 연결 종료"),
        Err(e) => {
            println!("웹소켓 서버 연결 실패: {}. 로컬 모드로 실행합니다.", e);
            run_local_mode(&node_names, monitor_interval).await?;
        }
    }
    
    Ok(())
}

// 웹소켓 처리 코드 수정
async fn handle_websocket(url: Url, server_id: String, node_names: Vec<String>) -> Result<(), Box<dyn Error>> {
    // 웹소켓 서버 연결
    println!("연결 시도 중: {}", url);
    
    // 단순한 연결 시도 (개발 환경에서 인증서 검증 비활성화는 환경 변수로 처리됨)
    let (ws_stream, _) = match connect_async(&url).await {
        Ok(conn) => {
            println!("웹소켓 서버에 연결되었습니다: {}", url);
            conn
        },
        Err(e) => {
            eprintln!("웹소켓 연결 실패: {:?}", e);
            return Err(Box::new(e));
        }
    };
    
    // 웹소켓 스트림 분리
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // 메트릭 전송 채널 생성
    let (tx, mut rx) = mpsc::channel::<String>(32);
    
    // 메트릭 수집 및 전송 루프
    let tx_clone = tx.clone();
    let node_names_clone = node_names.clone();
    let server_id_clone = server_id.clone();
    
    tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_secs(DEFAULT_MONITOR_INTERVAL));
        loop {
            interval.tick().await;
            
            // 시스템 정보 수집
            let sys_metrics = collect_system_metrics();
            
            // Docker 컨테이너 정보 수집
            let container_metrics = match collect_docker_metrics(&node_names_clone).await {
                Ok(metrics) => metrics,
                Err(e) => {
                    eprintln!("Docker 정보 수집 실패: {}", e);
                    vec![]
                },
            };
            
            // 서버로 전송할 데이터 구성
            let server_data = ServerData {
                server_id: server_id_clone.clone(),
                timestamp: chrono::Utc::now().timestamp() as u64,
                system: sys_metrics,
                containers: container_metrics,
            };
            
            // JSON으로 직렬화
            match serde_json::to_string(&server_data) {
                Ok(json) => {
                    if let Err(e) = tx_clone.send(json).await {
                        eprintln!("채널 전송 오류: {}", e);
                    }
                },
                Err(e) => {
                    eprintln!("JSON 직렬화 오류: {}", e);
                }
            }
        }
    });
    
    // 명령어 응답을 위한 채널
    let (cmd_tx, mut cmd_rx) = mpsc::channel::<CommandResponse>(32);
    
    // 웹소켓 수신 루프
    let cmd_tx_clone = cmd_tx.clone();
    tokio::spawn(async move {
        while let Some(msg) = ws_receiver.next().await {
            match msg {
                Ok(Message::Text(text)) => {
                    // 메시지 종류 확인 (일반 응답 또는 명령어)
                    if text.contains("\"type\":\"Command\"") {
                        // 명령어 메시지
                        handle_command_message(&text, &cmd_tx_clone).await;
                    } else {
                        println!("서버 메시지: {}", text);
                    }
                },
                Ok(Message::Close(_)) => {
                    println!("서버가 연결을 종료했습니다.");
                    break;
                },
                Err(e) => {
                    eprintln!("웹소켓 오류: {}", e);
                    break;
                },
                _ => {}
            }
        }
    });
    
    // 초기 메트릭 데이터 전송
    let initial_metrics = collect_system_metrics();
    let initial_containers = match collect_docker_metrics(&node_names).await {
        Ok(metrics) => metrics,
        Err(e) => {
            eprintln!("초기 Docker 정보 수집 실패: {}", e);
            vec![]
        },
    };
    
    let initial_data = ServerData {
        server_id: server_id.clone(),
        timestamp: chrono::Utc::now().timestamp() as u64,
        system: initial_metrics,
        containers: initial_containers,
    };
    
    let initial_json = serde_json::to_string(&initial_data)?;
    ws_sender.send(Message::Text(initial_json)).await?;
    
    // 메트릭 전송 및 명령어 응답 처리 루프
    loop {
        tokio::select! {
            // 메트릭 데이터 전송
            Some(json) = rx.recv() => {
                if let Err(e) = ws_sender.send(Message::Text(json)).await {
                    eprintln!("메시지 전송 실패: {}", e);
                    break;
                }
            }
            
            // 명령어 응답 전송
            Some(response) = cmd_rx.recv() => {
                // 명령어 응답을 CommandMessage::Response로 감싸기
                let response_msg = CommandMessage::Response(response);
                match serde_json::to_string(&response_msg) {
                    Ok(json) => {
                        if let Err(e) = ws_sender.send(Message::Text(json)).await {
                            eprintln!("명령어 응답 전송 실패: {}", e);
                        }
                    },
                    Err(e) => {
                        eprintln!("명령어 응답 직렬화 오류: {}", e);
                    }
                }
            }
        }
    }
    
    Ok(())
}

// 명령어 메시지 처리 함수
async fn handle_command_message(text: &str, cmd_tx: &mpsc::Sender<CommandResponse>) {
    // 메시지 파싱
    match serde_json::from_str::<CommandMessage>(text) {
        Ok(CommandMessage::Command(command)) => {
            println!("명령어 수신: {:?}", command);
            
            // 명령어 수신 응답 즉시 전송
            let received_response = CommandResponse {
                command_id: command.id.clone(),
                status: CommandStatus::Received,
                result: None,
                error: None,
                timestamp: chrono::Utc::now().timestamp() as u64,
            };
            
            // 응답 전송
            if let Err(e) = cmd_tx.send(received_response).await {
                eprintln!("명령어 수신 응답 전송 실패: {}", e);
                return;
            }
            
            // 별도 스레드에서 명령어 실행
            let cmd_tx_clone = cmd_tx.clone();
            let command_clone = command.clone();
            tokio::spawn(async move {
                // 명령어 실행
                println!("명령어 실행 중: {:?}", command_clone);
                
                // 명령어 핸들러 호출
                match CommandHandler::execute_command(&command_clone) {
                    Ok(response) => {
                        // 응답 전송
                        if let Err(e) = cmd_tx_clone.send(response).await {
                            eprintln!("명령어 실행 응답 전송 실패: {}", e);
                        }
                    },
                    Err(e) => {
                        // 오류 응답 전송
                        let error_response = CommandResponse {
                            command_id: command_clone.id.clone(),
                            status: CommandStatus::Failed,
                            result: None,
                            error: Some(e.message),
                            timestamp: chrono::Utc::now().timestamp() as u64,
                        };
                        
                        if let Err(e) = cmd_tx_clone.send(error_response).await {
                            eprintln!("명령어 오류 응답 전송 실패: {}", e);
                        }
                    }
                }
            });
        },
        Ok(CommandMessage::Response(_)) => {
            println!("예상치 못한 응답 메시지 수신: {}", text);
        },
        Err(e) => {
            eprintln!("명령어 메시지 파싱 오류: {}", e);
        }
    }
}

// run_local_mode 함수 수정
async fn run_local_mode(node_names: &[String], interval: u64) -> Result<(), Box<dyn Error>> {
    // stdout 변수 제거 (사용하지 않음)
    
    print!("{}", CLEAR_SCREEN);
    println!("{}{}크레딧코인 노드 실시간 모니터링 시작 (Ctrl+C로 종료){}", 
             STYLE_BOLD, COLOR_WHITE, COLOR_RESET);
    println!("-----------------------------------------");
    
    // 모니터링 루프
    let mut update_interval = time::interval(Duration::from_secs(interval));
    
    loop {
        // 새로운 데이터 수집
        let sys_metrics = collect_system_metrics();
        let container_metrics = match collect_docker_metrics(node_names).await {
            Ok(metrics) => metrics,
            Err(e) => {
                eprintln!("{}Docker 정보 수집 실패: {}{}", COLOR_RED, e, COLOR_RESET);
                vec![]
            },
        };
        
        // 화면 업데이트
        print!("{}", CLEAR_SCREEN);
        print_metrics(&sys_metrics, &container_metrics, interval);
        io::stdout().flush()?;
        
        // 다음 간격까지 대기
        update_interval.tick().await;
    }
}

// 메트릭 출력 함수
fn print_metrics(metrics: &SystemMetricsData, containers: &[ContainerMetricsData], interval: u64) {
    println!("{}{}CREDITCOIN NODE RESOURCE MONITOR{}                     {}", 
             STYLE_BOLD, COLOR_WHITE, COLOR_RESET,
             chrono::Local::now().format("%Y-%m-%d %H:%M:%S"));
    println!();
    
    // 시스템 정보 섹션
    println!("{}=== 시스템 정보 ==={}", 
             COLOR_YELLOW, COLOR_RESET);
    
    println!("호스트명: {}", metrics.host_name);
    println!("CPU 모델: {}", metrics.cpu_model);  // CPU 모델 정보 출력 추가
    
    // CPU 사용률 (색상으로 강조)
    let cpu_color = get_color_for_value(metrics.cpu_usage);
    println!("CPU 사용률: {}{:.2}%{} (코어: {}개)", 
             cpu_color, metrics.cpu_usage, COLOR_RESET, metrics.cpu_cores);
    
    // 메모리 사용률 (색상으로 강조)
    let mem_color = get_color_for_value(metrics.memory_used_percent);
    println!("메모리: {}{:.2}GB / {:.2}GB ({:.2}%){}",
             mem_color,
             metrics.memory_used as f64 / 1024.0 / 1024.0 / 1024.0,
             metrics.memory_total as f64 / 1024.0 / 1024.0 / 1024.0,
             metrics.memory_used_percent,
             COLOR_RESET);
    
    println!("스왑: {:.2}GB / {:.2}GB",
             metrics.swap_used as f64 / 1024.0 / 1024.0 / 1024.0,
             metrics.swap_total as f64 / 1024.0 / 1024.0 / 1024.0);
    
    // 디스크 정보 출력 추가
    let disk_percent = if metrics.disk_total > 0 {
        (metrics.disk_used as f64 / metrics.disk_total as f64) * 100.0
    } else {
        0.0
    };
    let disk_color = get_color_for_value(disk_percent as f32);
    println!("디스크: {}{:.2}GB / {:.2}GB ({:.2}%){}",
             disk_color,
             metrics.disk_used as f64 / 1024.0 / 1024.0 / 1024.0,
             metrics.disk_total as f64 / 1024.0 / 1024.0 / 1024.0,
             disk_percent,
             COLOR_RESET);
    
    // 업타임
    let days = metrics.uptime / 86400;
    let hours = (metrics.uptime % 86400) / 3600;
    let minutes = (metrics.uptime % 3600) / 60;
    println!("업타임: {}일 {}시간 {}분", days, hours, minutes);
    println!();
    
    // 컨테이너 정보 섹션
    println!("{}=== 컨테이너 정보 ==={}", 
             COLOR_YELLOW, COLOR_RESET);
    
    if containers.is_empty() {
        println!("모니터링 중인 컨테이너가 없습니다.");
    } else {
        // 헤더 출력
        println!("{}노드{}            {}CPU%{}    {}메모리 사용량{}          {}메모리%{}   {}네트워크 RX/TX{}", 
                 STYLE_BOLD, COLOR_RESET,
                 STYLE_BOLD, COLOR_RESET,
                 STYLE_BOLD, COLOR_RESET,
                 STYLE_BOLD, COLOR_RESET,
                 STYLE_BOLD, COLOR_RESET);
        
        // 각 컨테이너 정보 출력
        for container in containers {
            // CPU와 메모리 색상 가져오기
            let cpu_color = get_color_for_value(container.cpu_usage as f32);
            let mem_color = get_color_for_value(container.memory_percent as f32);
            
            // 메모리 단위 변환
            let memory_str = format_memory(container.memory_usage, container.memory_limit);
            
            // 네트워크 단위 변환
            let network_str = format!("{}/{}", 
                                     format_bytes(container.network_rx),
                                     format_bytes(container.network_tx));
            
            println!("{:<15} {}{:<8.2}{} {:<20} {}{:<8.2}{} {:<15}",
                     container.name,
                     cpu_color, container.cpu_usage, COLOR_RESET,
                     memory_str,
                     mem_color, container.memory_percent, COLOR_RESET,
                     network_str);
        }
    }
    
    // 아래에 상태 라인 추가
    println!();
    println!("{}[{}] 실시간 모니터링 중... (간격: {}초){}", 
             COLOR_CYAN,
             chrono::Local::now().format("%H:%M:%S"), 
             interval,
             COLOR_RESET);
}

// 값에 따른 색상 문자열 선택 함수
fn get_color_for_value(value: f32) -> &'static str {
    if value > 80.0 {
        COLOR_RED
    } else if value > 50.0 {
        COLOR_YELLOW
    } else {
        COLOR_GREEN
    }
}

// 시스템 메트릭 수집
fn collect_system_metrics() -> SystemMetricsData {
    let mut sys = System::new_all();
    sys.refresh_all();
    
    let memory_total = sys.total_memory();
    let memory_used = sys.used_memory();
    let memory_percent = if memory_total > 0 {
        (memory_used as f32 / memory_total as f32) * 100.0
    } else {
        0.0
    };
    
    // CPU 모델 정보 수집
    let cpu_model = if sys.cpus().len() > 0 {
        // 첫 번째 CPU의 브랜드 이름 가져오기
        sys.cpus()[0].brand().to_string()
    } else {
        String::from("Unknown CPU")
    };
    
    // 디스크 정보 수집 추가
    let mut disk_total = 0;
    let mut disk_used = 0;
    
    // macOS, Linux에서 작동하는 방식
    if cfg!(target_os = "macos") || cfg!(target_os = "linux") {
        // df 명령어로 루트 디렉토리의 디스크 정보 가져오기
        if let Ok(output) = std::process::Command::new("df")
            .args(&["-k", "/"]) // 킬로바이트 단위로 루트 디렉토리 정보
            .output() 
        {
            let output_str = String::from_utf8_lossy(&output.stdout);
            if let Some(line) = output_str.lines().nth(1) { // 두 번째 줄에 데이터가 있음
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 {
                    // 킬로바이트 단위를 바이트로 변환 (1024 곱하기)
                    disk_total = parts[1].parse::<u64>().unwrap_or(0) * 1024;
                    disk_used = parts[2].parse::<u64>().unwrap_or(0) * 1024;
                }
            }
        }
    } else if cfg!(target_os = "windows") {
        // Windows에서는 다른 방법 사용 필요 (예시)
        // PowerShell이나 WMI 사용해 디스크 정보 가져오기
        if let Ok(output) = std::process::Command::new("powershell")
            .args(&["-Command", "Get-PSDrive C | Select-Object Used,Free"])
            .output()
        {
            let output_str = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = output_str.lines().collect();
            if lines.len() >= 3 {
                let values: Vec<&str> = lines[2].split_whitespace().collect();
                if values.len() >= 2 {
                    let used = values[0].parse::<u64>().unwrap_or(0);
                    let free = values[1].parse::<u64>().unwrap_or(0);
                    disk_used = used;
                    disk_total = used + free;
                }
            }
        }
    }
    
    SystemMetricsData {
        host_name: sys.host_name().unwrap_or_else(|| "알 수 없음".to_string()),
        cpu_model,  // CPU 모델 정보 추가
        cpu_usage: sys.global_cpu_info().cpu_usage(),
        cpu_cores: sys.physical_core_count().unwrap_or(0),
        memory_total,
        memory_used,
        memory_used_percent: memory_percent,
        swap_total: sys.total_swap(),
        swap_used: sys.used_swap(),
        uptime: sys.uptime(),
        disk_total, // 디스크 총량 추가
        disk_used,  // 디스크 사용량 추가
    }
}

// Docker 컨테이너 메트릭 수집
async fn collect_docker_metrics(node_filter: &[String]) -> Result<Vec<ContainerMetricsData>, Box<dyn Error>> {
    // Docker API 연결
    let docker = Docker::connect_with_local_defaults()?;
    
    // 컨테이너 목록 가져오기
    let mut filters = HashMap::new();
    filters.insert("status".to_string(), vec!["running".to_string()]);
    
    let containers = docker.list_containers(Some(ListContainersOptions {
        all: true,
        filters,
        ..Default::default()
    })).await?;
    
    let mut container_metrics = Vec::new();
    
    // 각 컨테이너 분석
    for container in containers {
        let id = container.id.clone().unwrap_or_default();
        
        // 컨테이너 이름에서 슬래시 제거
        let names = container.names.clone().unwrap_or_default();
        let name = names.get(0)
            .map(|n| n.trim_start_matches('/'))
            .unwrap_or("unknown");
        
        // 필터링: 노드 이름 목록에 포함된 컨테이너만 처리
        if !node_filter.is_empty() && !node_filter.iter().any(|filter| name.contains(filter)) {
            continue;
        }
        
        let status = container.status.clone().unwrap_or_default();
        
        // 컨테이너 별명 (nickname) 설정
        // 예: "3node0" -> "Creditcoin 3.0 Node 0", "node1" -> "Creditcoin 2.0 Node 1"
        let nickname = if name.starts_with("3node") {
            Some(format!("Creditcoin 3.0 Node {}", &name[5..]))
        } else if name.starts_with("node") {
            Some(format!("Creditcoin 2.0 Node {}", &name[4..]))
        } else {
            None
        };
        
        // 컨테이너 통계 수집 (비스트리밍 모드)
        let stats_options = StatsOptions {
            stream: false,
            ..Default::default()
        };
        
        // 스트림 대신 단일 stats 객체를 가져옴
        if let Ok(stats) = docker.stats(&id, Some(stats_options)).try_next().await {
            if let Some(stats) = stats {
                // CPU 사용률 계산
                let cpu_delta = stats.cpu_stats.cpu_usage.total_usage as f64 - 
                                stats.precpu_stats.cpu_usage.total_usage as f64;
                
                let system_delta = stats.cpu_stats.system_cpu_usage.unwrap_or(0) as f64 - 
                                  stats.precpu_stats.system_cpu_usage.unwrap_or(0) as f64;
                
                let cpu_usage = if system_delta > 0.0 && cpu_delta > 0.0 {
                    (cpu_delta / system_delta) * 100.0 * stats.cpu_stats.online_cpus.unwrap_or(1) as f64
                } else {
                    0.0
                };
                
                // 메모리 사용량
                let memory_usage = stats.memory_stats.usage.unwrap_or(0);
                let memory_limit = stats.memory_stats.limit.unwrap_or(0);
                let memory_percent = if memory_limit > 0 {
                    (memory_usage as f64 / memory_limit as f64) * 100.0
                } else {
                    0.0
                };
                
                // 네트워크 사용량
                let (rx_bytes, tx_bytes) = match &stats.networks {
                    Some(networks) => {
                        let mut rx = 0;
                        let mut tx = 0;
                        for (_, net_stats) in networks {
                            rx += net_stats.rx_bytes;
                            tx += net_stats.tx_bytes;
                        }
                        (rx, tx)
                    },
                    None => (0, 0),
                };
                
                container_metrics.push(ContainerMetricsData {
                    name: name.to_string(),
                    id,
                    status,
                    cpu_usage,
                    memory_usage,
                    memory_limit,
                    memory_percent,
                    network_rx: rx_bytes,
                    network_tx: tx_bytes,
                    nickname,
                });
            }
        }
    }
    
    Ok(container_metrics)
}

// 메모리 단위 변환 함수
fn format_memory(usage: u64, limit: u64) -> String {
    let usage_mb = usage as f64 / 1024.0 / 1024.0;
    let limit_mb = limit as f64 / 1024.0 / 1024.0;
    
    if limit_mb > 1024.0 {
        format!("{:.2}GB / {:.2}GB", usage_mb / 1024.0, limit_mb / 1024.0)
    } else {
        format!("{:.0}MB / {:.0}MB", usage_mb, limit_mb)
    }
}

// 바이트 단위 변환 함수
fn format_bytes(bytes: u64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    
    let bytes = bytes as f64;
    
    if bytes >= GB {
        format!("{:.2}GB", bytes / GB)
    } else if bytes >= MB {
        format!("{:.2}MB", bytes / MB)
    } else if bytes >= KB {
        format!("{:.2}KB", bytes / KB)
    } else {
        format!("{}B", bytes)
    }
}