//! Play through a Ragnarok Offline invitation link (`https://host/#invite=TOKEN`).
//!
//! The host's sharing gateway only speaks HTTPS: an invitation is exchanged for a session cookie
//! (`POST /_friend/exchange`), and each game server is then reachable as a WebSocket at
//! `/ws/<ip>:<port>` that relays raw TCP bytes. `open` returns one end of an in-memory pipe whose
//! other end is pumped to that WebSocket, so the packet code above reads and writes bytes exactly
//! as it does over TCP.

use std::io;
use std::net::IpAddr;
use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream};
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;
use tokio_rustls::client::TlsStream;
use tokio_rustls::rustls::pki_types::ServerName;
use tokio_rustls::rustls::{ClientConfig, RootCertStore};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;

const COOKIE: &str = "__Host-ro-friend";

#[derive(Clone, Debug)]
pub struct Tunnel {
    host: String,
    invite: String,
    cookie: Option<String>,
}

impl Tunnel {
    /// Accepts the invitation link as the app copies it. Anything else is `None`.
    pub fn parse(link: &str) -> Option<Self> {
        let rest = link.trim().strip_prefix("https://")?;
        let (host, fragment) = rest.split_once('#')?;
        let host = host.trim_end_matches('/');
        let invite = fragment.strip_prefix("invite=")?;
        let valid = |s: &str, max: usize| {
            !s.is_empty() && s.len() <= max && s.bytes().all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
        };
        (valid(host, 253) && !host.contains('/') && valid(invite, 64)).then(|| Self {
            host: host.to_string(),
            invite: invite.to_string(),
            cookie: None,
        })
    }

    /// The gateway path for a game server address. The login entry names the tunnel's own host,
    /// which stands for the host's login server; char/map redirects carry the IP the server
    /// advertised, which the gateway accepts as is.
    fn path(addr: &str) -> io::Result<String> {
        let (host, port) = addr
            .rsplit_once(':')
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "address without port"))?;
        Ok(if host.parse::<IpAddr>().is_ok() {
            format!("/ws/{host}:{port}")
        } else {
            format!("/ws/127.0.0.1:{port}")
        })
    }

    async fn tls(&self) -> io::Result<TlsStream<TcpStream>> {
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        let config = ClientConfig::builder_with_provider(Arc::new(
            tokio_rustls::rustls::crypto::ring::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .map_err(io::Error::other)?
        .with_root_certificates(roots)
        .with_no_client_auth();
        let name = ServerName::try_from(self.host.clone()).map_err(io::Error::other)?;
        let tcp = TcpStream::connect((self.host.as_str(), 443)).await?;
        TlsConnector::from(Arc::new(config)).connect(name, tcp).await
    }

    /// Trades the invitation for a session cookie.
    async fn exchange(&mut self) -> io::Result<()> {
        let body = format!("{{\"invite\":\"{}\"}}", self.invite);
        let request = format!(
            "POST /_friend/exchange HTTP/1.1\r\nHost: {h}\r\nOrigin: https://{h}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len(),
            h = self.host
        );
        let mut stream = self.tls().await?;
        stream.write_all(request.as_bytes()).await?;
        let mut reply = Vec::new();
        // The reply is a few hundred bytes; a TLS peer closing without close_notify still left it in `reply`.
        let _ = stream.take(64 * 1024).read_to_end(&mut reply).await;
        let reply = String::from_utf8_lossy(&reply);
        let status = reply.split(' ').nth(1).unwrap_or("");
        if status != "200" {
            let reason = reply.split("\r\n\r\n").nth(1).unwrap_or("").trim();
            return Err(io::Error::new(
                io::ErrorKind::PermissionDenied,
                format!("invitation refused ({status}): {reason}"),
            ));
        }
        let cookie = reply
            .lines()
            .filter_map(|l| l.split_once(':'))
            .filter(|(k, _)| k.eq_ignore_ascii_case("set-cookie"))
            .filter_map(|(_, v)| v.trim().split(';').next())
            .find(|c| c.starts_with(COOKIE))
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "gateway sent no session cookie"))?;
        self.cookie = Some(cookie.to_string());
        Ok(())
    }

    async fn websocket(
        &self,
        path: &str,
    ) -> io::Result<tokio_tungstenite::WebSocketStream<TlsStream<TcpStream>>> {
        let mut request = format!("wss://{}{path}", self.host)
            .into_client_request()
            .map_err(io::Error::other)?;
        let headers = request.headers_mut();
        let origin = format!("https://{}", self.host);
        headers.insert("Origin", HeaderValue::from_str(&origin).map_err(io::Error::other)?);
        if let Some(cookie) = &self.cookie {
            headers.insert("Cookie", HeaderValue::from_str(cookie).map_err(io::Error::other)?);
        }
        let (ws, _) = tokio_tungstenite::client_async(request, self.tls().await?)
            .await
            .map_err(io::Error::other)?;
        Ok(ws)
    }

    /// Connects to the game server at `addr` through the gateway.
    pub async fn open(&mut self, addr: &str) -> io::Result<DuplexStream> {
        let path = Self::path(addr)?;
        if self.cookie.is_none() {
            self.exchange().await?;
        }
        let ws = match self.websocket(&path).await {
            Ok(ws) => ws,
            // A restarted gateway forgets sessions: one fresh exchange, then give up.
            Err(_) => {
                self.exchange().await?;
                self.websocket(&path).await?
            }
        };
        let (near, far) = tokio::io::duplex(64 * 1024);
        tokio::spawn(pump(ws, far));
        Ok(near)
    }
}

async fn pump(ws: tokio_tungstenite::WebSocketStream<TlsStream<TcpStream>>, pipe: DuplexStream) {
    let (mut ws_tx, mut ws_rx) = ws.split();
    let (mut pipe_rx, mut pipe_tx) = tokio::io::split(pipe);
    let mut buf = vec![0u8; 16 * 1024];
    loop {
        tokio::select! {
            n = pipe_rx.read(&mut buf) => match n {
                Ok(0) | Err(_) => break,
                Ok(n) => if ws_tx.send(Message::binary(buf[..n].to_vec())).await.is_err() { break },
            },
            msg = ws_rx.next() => match msg {
                Some(Ok(Message::Binary(data))) => if pipe_tx.write_all(&data).await.is_err() { break },
                Some(Ok(Message::Text(text))) => if pipe_tx.write_all(text.as_bytes()).await.is_err() { break },
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                Some(Ok(_)) => {}
            },
        }
    }
    let _ = ws_tx.close().await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_invitation_links() {
        let t = Tunnel::parse("https://ro.namike.me/#invite=abc_DEF-123").unwrap();
        assert_eq!((t.host.as_str(), t.invite.as_str()), ("ro.namike.me", "abc_DEF-123"));
        assert!(Tunnel::parse("http://ro.namike.me/#invite=x").is_none());
        assert!(Tunnel::parse("https://ro.namike.me/").is_none());
        assert!(Tunnel::parse("https://ro.namike.me/#invite=a\"b").is_none());
    }

    #[test]
    fn maps_addresses_to_gateway_paths() {
        assert_eq!(Tunnel::path("ro.namike.me:6900").unwrap(), "/ws/127.0.0.1:6900");
        assert_eq!(Tunnel::path("127.0.0.1:6121").unwrap(), "/ws/127.0.0.1:6121");
        assert_eq!(Tunnel::path("10.0.2.15:5121").unwrap(), "/ws/10.0.2.15:5121");
    }
}
