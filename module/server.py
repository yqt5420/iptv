from http.server import HTTPServer, SimpleHTTPRequestHandler

class CustomHTTPRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        # 检查请求的路径是否是.m3u8文件
        if self.path.endswith('.m3u8'):
            self.send_response(200)  # 发送HTTP状态码200
            self.send_header('Content-type', 'application/vnd.apple.mpegurl')  # 设置MIME类型
            self.end_headers()
            # 打开并读取.m3u8文件内容
            with open('m3u8.m3u', 'rb') as file:  # 注意文件名和路径
                file_content = file.read()
                self.wfile.write(file_content)
        else:
            # 处理其他类型的请求
            super().do_GET()

def run(server_class=HTTPServer, handler_class=CustomHTTPRequestHandler):
    server_address = ('', 8000)  # 监听所有IP地址，端口号8000
    httpd = server_class(server_address, handler_class)
    print("Server started at http://localhost:8000")
    httpd.serve_forever()

if __name__ == '__main__':
    run()