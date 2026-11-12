# Tiny HTTPS test server. Usage: python3 -I httpsd.py <port> <docroot> <cert> <key> <http-redirect-target>
# GET /ok.zip -> docroot/good.zip ; GET /redir.zip -> 302 to <http-redirect-target> ; GET /big.zip -> 200 oversize
import http.server, ssl, sys, os
port, root, cert, key, target = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path == "/redir.zip":
            self.send_response(302); self.send_header("Location", target); self.end_headers(); return
        name = {"/ok.zip": "good.zip", "/big.zip": "oversize.zip"}.get(self.path)
        if not name:
            self.send_response(404); self.end_headers(); return
        data = open(os.path.join(root, name), "rb").read()
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(cert, key)
srv = http.server.HTTPServer(("127.0.0.1", port), H); srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
