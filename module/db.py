import sqlite3


#定义链接数据库的类，有初始化数据库，链接数据库，写入数据库，关闭数据库，查询数据库方法
class Database:
    def __init__(self, db):
        self.conn = sqlite3.connect(db)
        self.cur = self.conn.cursor()
        # 创建3个表
        self.ip_sql= "CREATE TABLE IF NOT EXISTS ip (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT)"
        self.channel_sql= "CREATE TABLE IF NOT EXISTS channel (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT, url TEXT)"
        self.result_sql= "CREATE TABLE IF NOT EXISTS result (id INTEGER PRIMARY KEY AUTOINCREMENT, channel TEXT, url TEXT, speed TEXT)"
        self.cur.execute(self.ip_sql)
        self.cur.execute(self.channel_sql)
        self.cur.execute(self.result_sql)
        self.conn.commit()


                    
    def create_table(self, table):
        # 创建表
        self.sql= "CREATE TABLE IF NOT EXISTS " + table + " (id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT)"
        self.cur.execute(self.sql)
        self.conn.commit() 
        print(f'{table} 表创建成功') 
        
    
    def insert(self, table, value):
        # 写入数据
        self.sql = "INSERT INTO " + table + " (value) VALUES ('" + str(value) + "')"
        # print(self.sql)
        self.cur.execute(self.sql)
        self.conn.commit()
        # print(f'{value} 写入成功')
        return True

    def insert_channel(self, channel, url):
        # 写入数据
        self.sql = "INSERT INTO channel (channel, url) VALUES (?, ?)"
        self.cur.execute(self.sql, (channel, url))
        self.conn.commit()
        # print(f'{channel} 写入成功')
        
    
    def insert_result(self, channel, url, speed):
        # 写入测试后数据
        self.sql = "INSERT INTO result (channel, url, speed) VALUES (?, ?, ?)"
        self.cur.execute(self.sql, (channel, url, speed))
        self.conn.commit()
        # print(f'{channel} 写入成功')
        
        
    def view(self, table):
        # 查询数据  
        self.cur.execute("SELECT * FROM " + table)
        rows = self.cur.fetchall()
        return rows

    def delete(self, table):
        # 删除所有数据
        self.cur.execute("DELETE FROM " + table)
        print('删除成功')
        self.conn.commit()
        
    def close(self):
        # 关闭数据库
        self.cur.close()
        self.conn.close()   
        
    def update(self, table, ips):
        # 更新数据
        self.delete(table)
        self.insert(table, ips)
        print(f'{ips} 更新成功')
    
    
if __name__ == '__main__':
    db = Database('ip4.db')
    
# db = Database('ip.db')
# db.delete('channel')
# r = db.view('channel')
# r= [[i[1], i[2]] for i in r]
# print(r)
# ip_db.create_table('ip')   
# # ip_db.insert('ip', '127.0.0.1')
# # # ip_db.close()
# d = ip_db.view('ip')
# print(d)
