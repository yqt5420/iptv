import asyncio  
import re
import urllib
import json
import aiohttp
from module.db import Database
import base64


class IP():

    #获取响应内容
    async def requests(self, session, url):
        async with session.get(url) as response:
            return await response.text()


    async def fofa(self, url):
        try:
            async with aiohttp.ClientSession() as session:
                html = await self.requests(session, url)
            await asyncio.sleep(5)
            pattern = r"http://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+"  # 设置匹配的格式，如http://8.8.8.8:8888
            ips = re.findall(pattern, html)
            ips = set(ips)
            return ips
        except Exception as e:
            print(f'请求fofa失败：{e}')
            return []



    async def zoomeye(self, url):
        try:
            async with aiohttp.ClientSession() as session:  
                html = await self.requests(session, url)
            await asyncio.sleep(4)
            html = json.loads(html)['matches']
            ips = [i['portinfo']['service'] + "://" + i['ip'] + ':' + str(i['portinfo']['port']) for i in html if 'http' or 'https' in i['portinfo']['service']]
            ips = set(ips)
            return ips
        except Exception as e:
            print(f'请求zoomeye.org接口失败：{e}')
            return []

    async def zoomeye_task(self):
        citys = ['beijing', 'tianjin', 'hebei', 'shanxi', 'neimenggu', 'liaoning', 'jilin', 'heilongjiang', 'shanghai', 'jiangsu', 'zhejiang', 'anhui', 'fujian', 'jiangxi', 'shandong', 'henan', 'hubei', 'hunan', 'guangdong', 'hainan', 'chongqing', 'sichuan', 'guizhou', 'yunnan', 'shanxi', 'gansu', 'qinghai', 'ningxia', 'xinjiang', 'xizang']
        keys = ['/iptv/live/zh_cn.js +country:"CN" +subdivisions:"' + city + '"' for city in citys]
        zoom_url = 'https://www.zoomeye.org/api/search?q='
        urls = [zoom_url + urllib.parse.quote(key) for key in keys]
        ips = []
        for url in urls:
            print(f'正在访问{url},请稍等...')
            ip = await self.zoomeye(url)
            print(f'获取到{len(ip)}个ip')
            ips += ip
        return ips
    
    async def fofa_task(self):
        citys = ['beijing', 'tianjin', 'hebei', 'shanxi', 'neimenggu', 'liaoning', 'jilin', 'heilongjiang', 'shanghai', 'jiangsu', 'zhejiang', 'anhui', 'fujian', 'jiangxi', 'shandong', 'henan', 'hubei', 'hunan', 'guangdong', 'hainan', 'chongqing', 'sichuan', 'guizhou', 'yunnan', 'shanxi', 'gansu', 'qinghai', 'ningxia', 'xinjiang', 'xizang']
        base_url = 'https://fofa.info/result?qbase64='
        key = ['"iptv/live/zh_cn.js" && country="CN" && region="' + city + '"' for city in citys]
        urls = [base_url + base64.b64encode(key[i].encode('utf-8')).decode('utf-8') for i in range(len(key))]
        ips = []
        for url in urls:
            print(f'正在访问{url},请稍等...')
            ip = await self.fofa(url)
            print(f'获取到{len(ip)}个ip')
            ips += ip
        return ips
        
    async def update_datebase(self, ips):
        try:
            ip_db = Database('ip.db')
            db_ip = ip_db.view('ip')
            new_ips = [i for i in ips if i not in db_ip]
            print(f'共获取到{len(new_ips)}个新ip')
            for ip in new_ips:
                ip_db.insert('ip', ip)
            ip_db.close()
        except Exception as e:
            print(f'更新数据库失败：{e}')


    async def update(self):
        try:
            print('开始获取更新数据库...')
            z_ips = await self.zoomeye_task()
            f_ips = await self.fofa_task()
            ips = z_ips + f_ips
            if ips:
                await self.update_datebase(ips)
            else:
                print('未找到ip，被反爬了，明天再试吧！')
        except Exception as e:
            print(f'更新数据库失败：{e}')
    



if __name__ == '__main__':
    ip = IP()
    asyncio.run(ip.update())
         
 
 
 
 
 
 
 
 
 
 
 
  