#!/usr/bin/env python3
"""
Simple test server to receive form submissions on port 8888.
Returns JSON responses and allows CORS.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import datetime

class CORSRequestHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        """Handle preflight CORS request"""
        self.send_response(200)
        self.send_cors_headers()
        self.end_headers()

    def do_POST(self):
        """Handle POST request with form data"""
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        try:
            # Parse JSON data
            data = json.loads(post_data.decode('utf-8'))
            print(f"\n[{datetime.datetime.now().strftime('%H:%M:%S')}] Received form submission:")
            print(json.dumps(data, indent=2))
            
            # Send success response
            self.send_response(200)
            self.send_cors_headers()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            response = {
                "status": "success",
                "message": "Form data received successfully",
                "timestamp": datetime.datetime.now().isoformat(),
                "received_data": data
            }
            self.wfile.write(json.dumps(response).encode('utf-8'))
            
        except json.JSONDecodeError:
            # Send error response for invalid JSON
            self.send_response(400)
            self.send_cors_headers()
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            error_response = {
                "status": "error",
                "message": "Invalid JSON data"
            }
            self.wfile.write(json.dumps(error_response).encode('utf-8'))
    
    def send_cors_headers(self):
        """Add CORS headers to allow requests from the dev server"""
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    
    def log_message(self, format, *args):
        """Custom log format"""
        print(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] {format % args}")

if __name__ == '__main__':
    server_address = ('', 8888)
    httpd = HTTPServer(server_address, CORSRequestHandler)
    print(f"Test server running on http://localhost:8888")
    print(f"Ready to receive form submissions...")
    print(f"Press Ctrl+C to stop\n")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")