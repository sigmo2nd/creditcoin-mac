// client_command_handler.rs - 클라이언트측 명령어 처리 기능 구현

use serde::{Serialize, Deserialize};
use std::process::Command as ProcessCommand;
use std::collections::HashMap;
use std::error::Error;
use std::fmt;

// 명령어 종류
#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum CommandType {
    Start,              // 노드 시작
    Stop,               // 노드 중지
    Restart,            // 노드 재시작
    Payout,             // 페이아웃 실행
    PayoutAll,          // 모든 노드 페이아웃
    RebootServer,       // 서버 재부팅
    Custom(String),     // 커스텀 명령어
}

// 명령어 대상
#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum CommandTarget {
    Node(String),       // 특정 노드 (노드명)
    AllNodes,           // 모든 노드
    Server,             // 서버 전체
}

// 명령어 구조체
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Command {
    pub id: String,                 // 명령어 ID
    pub command_type: CommandType,  // 명령어 종류
    pub target: CommandTarget,      // 명령어 대상
    pub parameters: Option<HashMap<String, String>>, // 추가 매개변수
    pub timestamp: u64,             // 생성 시간
}

// 명령어 응답 상태
#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum CommandStatus {
    Received,           // 수신됨
    InProgress,         // 실행 중
    Completed,          // 완료됨
    Failed,             // 실패
}

// 명령어 응답 구조체
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct CommandResponse {
    pub command_id: String,         // 원본 명령어 ID
    pub status: CommandStatus,      // 상태
    pub result: Option<String>,     // 결과 (선택 사항)
    pub error: Option<String>,      // 오류 메시지 (실패 시)
    pub timestamp: u64,             // 응답 시간
}

// 명령어 메시지 (서버와 클라이언트 간 통신에 사용)
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum CommandMessage {
    Command(Command),
    Response(CommandResponse),
}

// 명령어 처리 오류
#[derive(Debug)]
pub struct CommandError {
    pub message: String,
}

impl fmt::Display for CommandError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "명령어 실행 오류: {}", self.message)
    }
}

impl Error for CommandError {}

impl From<std::io::Error> for CommandError {
    fn from(error: std::io::Error) -> Self {
        CommandError {
            message: format!("IO 오류: {}", error),
        }
    }
}

// 명령어 핸들러 - 실제로 명령어 실행
pub struct CommandHandler;

impl CommandHandler {
    // 명령어 처리 (OS 명령어 실행)
    pub fn execute_command(command: &Command) -> Result<CommandResponse, CommandError> {
        println!("명령어 실행 중: {:?}", command);
        
        // 실행 시작 응답
        let mut response = CommandResponse {
            command_id: command.id.clone(),
            status: CommandStatus::InProgress,
            result: None,
            error: None,
            timestamp: chrono::Utc::now().timestamp() as u64,
        };
        
        // 명령어 실행
        let result = match command.command_type {
            CommandType::Start => Self::handle_start(&command.target),
            CommandType::Stop => Self::handle_stop(&command.target),
            CommandType::Restart => Self::handle_restart(&command.target),
            CommandType::Payout => Self::handle_payout(&command.target),
            CommandType::PayoutAll => Self::handle_payout_all(),
            CommandType::RebootServer => Self::handle_reboot_server(),
            CommandType::Custom(ref cmd) => Self::handle_custom_command(cmd),
        };
        
        // 결과 처리
        match result {
            Ok(output) => {
                response.status = CommandStatus::Completed;
                response.result = Some(output);
            },
            Err(e) => {
                response.status = CommandStatus::Failed;
                response.error = Some(e.message);
            }
        }
        
        Ok(response)
    }
    
    // 노드 시작 명령어 처리
    fn handle_start(target: &CommandTarget) -> Result<String, CommandError> {
        match target {
            CommandTarget::Node(node_name) => {
                // Docker에서 노드 컨테이너 시작
                let output = ProcessCommand::new("docker")
                    .args(&["start", node_name])
                    .output()?;
                
                if output.status.success() {
                    Ok(format!("노드 '{}' 시작 성공", node_name))
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("노드 시작 실패: {}", error) })
                }
            },
            CommandTarget::AllNodes => {
                // 모든 노드 시작 (startAll 함수 호출)
                let output = ProcessCommand::new("bash")
                    .args(&["-c", "source ~/.zshrc || source ~/.bash_profile; startAll"])
                    .output()?;
                
                if output.status.success() {
                    Ok("모든 노드 시작 성공".to_string())
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("모든 노드 시작 실패: {}", error) })
                }
            },
            _ => Err(CommandError { message: "지원되지 않는 시작 대상입니다".to_string() }),
        }
    }
    
    // 노드 중지 명령어 처리
    fn handle_stop(target: &CommandTarget) -> Result<String, CommandError> {
        match target {
            CommandTarget::Node(node_name) => {
                // Docker에서 노드 컨테이너 중지
                let output = ProcessCommand::new("docker")
                    .args(&["stop", node_name])
                    .output()?;
                
                if output.status.success() {
                    Ok(format!("노드 '{}' 중지 성공", node_name))
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("노드 중지 실패: {}", error) })
                }
            },
            CommandTarget::AllNodes => {
                // 모든 노드 중지 (stopAll 함수 호출)
                let output = ProcessCommand::new("bash")
                    .args(&["-c", "source ~/.zshrc || source ~/.bash_profile; stopAll"])
                    .output()?;
                
                if output.status.success() {
                    Ok("모든 노드 중지 성공".to_string())
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("모든 노드 중지 실패: {}", error) })
                }
            },
            _ => Err(CommandError { message: "지원되지 않는 중지 대상입니다".to_string() }),
        }
    }
    
    // 노드 재시작 명령어 처리
    fn handle_restart(target: &CommandTarget) -> Result<String, CommandError> {
        match target {
            CommandTarget::Node(node_name) => {
                // Docker에서 노드 컨테이너 재시작
                let output = ProcessCommand::new("docker")
                    .args(&["restart", node_name])
                    .output()?;
                
                if output.status.success() {
                    Ok(format!("노드 '{}' 재시작 성공", node_name))
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("노드 재시작 실패: {}", error) })
                }
            },
            CommandTarget::AllNodes => {
                // 모든 노드 재시작 (restartAll 함수 호출)
                let output = ProcessCommand::new("bash")
                    .args(&["-c", "source ~/.zshrc || source ~/.bash_profile; restartAll"])
                    .output()?;
                
                if output.status.success() {
                    Ok("모든 노드 재시작 성공".to_string())
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("모든 노드 재시작 실패: {}", error) })
                }
            },
            CommandTarget::Server => {
                // 서버 재시작 명령 (재부팅과 다름)
                // 이 부분은 필요에 따라 구현
                Err(CommandError { message: "서버 재시작은 현재 지원되지 않습니다".to_string() })
            }
        }
    }
    
    // 페이아웃 명령어 처리
    fn handle_payout(target: &CommandTarget) -> Result<String, CommandError> {
        match target {
            CommandTarget::Node(node_name) => {
                // 특정 노드 페이아웃 (payout 함수 호출)
                let output = ProcessCommand::new("bash")
                    .args(&["-c", &format!("source ~/.zshrc || source ~/.bash_profile; payout {}", node_name)])
                    .output()?;
                
                if output.status.success() {
                    let result = String::from_utf8_lossy(&output.stdout);
                    Ok(format!("노드 '{}' 페이아웃 성공:\n{}", node_name, result))
                } else {
                    let error = String::from_utf8_lossy(&output.stderr);
                    Err(CommandError { message: format!("노드 페이아웃 실패: {}", error) })
                }
            },
            _ => Err(CommandError { message: "지원되지 않는 페이아웃 대상입니다".to_string() }),
        }
    }
    
    // 모든 노드 페이아웃 명령어 처리
    fn handle_payout_all() -> Result<String, CommandError> {
        // 모든 노드 페이아웃 (payoutAll 함수 호출)
        let output = ProcessCommand::new("bash")
            .args(&["-c", "source ~/.zshrc || source ~/.bash_profile; payoutAll"])
            .output()?;
        
        if output.status.success() {
            let result = String::from_utf8_lossy(&output.stdout);
            Ok(format!("모든 노드 페이아웃 성공:\n{}", result))
        } else {
            let error = String::from_utf8_lossy(&output.stderr);
            Err(CommandError { message: format!("모든 노드 페이아웃 실패: {}", error) })
        }
    }
    
    // 서버 재부팅 명령어 처리
    fn handle_reboot_server() -> Result<String, CommandError> {
        // 시스템 재부팅 (sudo 사용)
        // 주의: 이 기능은 보안 상 위험할 수 있으므로 신중히 사용해야 함
        let output = ProcessCommand::new("sudo")
            .args(&["shutdown", "-r", "now"])
            .output()?;
        
        if output.status.success() {
            Ok("서버 재부팅 명령이 전송되었습니다".to_string())
        } else {
            let error = String::from_utf8_lossy(&output.stderr);
            Err(CommandError { message: format!("서버 재부팅 실패: {}", error) })
        }
    }
    
    // 커스텀 명령어 처리
    fn handle_custom_command(cmd: &str) -> Result<String, CommandError> {
        // 커스텀 명령어 실행 (보안상 위험할 수 있음)
        // 실제 구현에서는 허용된 명령어 목록으로 제한하는 것이 좋음
        let output = ProcessCommand::new("bash")
            .args(&["-c", cmd])
            .output()?;
        
        if output.status.success() {
            let result = String::from_utf8_lossy(&output.stdout);
            Ok(format!("커스텀 명령어 실행 성공:\n{}", result))
        } else {
            let error = String::from_utf8_lossy(&output.stderr);
            Err(CommandError { message: format!("커스텀 명령어 실행 실패: {}", error) })
        }
    }
}