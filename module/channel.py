# -*- coding:utf-8 -*-
import asyncio
import aiohttp
import re
from module.db import Database
import json


class CHANNEL():
    def __init__(self):
        self.db = Database('ip.db')
        self.semaphore = asyncio.Semaphore(5000)


    
    # def name_convert(self, name):
    #     # 定义替换规则
    #     replace_rules = {
    #     r"cctv|中央|央视": "CCTV",
    #     r"高清|超高|HD|标清|频道|-| |\+|＋|\(|\)": "",
    #     r"CCTV(\d)\S{1,4}": r"CCTV\1",
    #     r"CCTV(\d\d)\S{1,4}": r"CCTV\1",
    #     r"CCTV1综合|CCTV2财经|CCTV3综艺|CCTV4国际|CCTV4中文国际|CCTV4欧洲|CCTV5体育|CCTV6电影|CCTV7军事|CCTV7军农|CCTV7农业|CCTV7国防军事|CCTV8电视剧|CCTV9记录|CCTV9纪录|CCTV10科教|CCTV11戏曲|CCTV12社会与法|CCTV13新闻|CCTV新闻|CCTV14少儿|CCTV15音乐|CCTV16奥林匹克|CCTV17农业农村|CCTV17农业|CCTV5\+体育赛视|CCTV5\+体育赛事|CCTV5\+体育": lambda match: match.group(0).replace("体育赛视", "").replace("体育赛事", "")
    # }

    #     # 应用替换规则
    #     for pattern, replacement in replace_rules.items():
    #         name = re.sub(pattern, replacement, name)
    #     return name
    

    def name_convert(self, name):
        # 定义替换规则
        replace_rules = {
        r"cctv|中央|央视": "CCTV",
        r"高清|超高|HD|标清|频道|-| |\+|＋|\(|\)": "",
        r"CCTV(\d+).*": r"CCTV-\1" }

        # 应用替换规则
        for pattern, replacement in replace_rules.items():
            name = re.sub(pattern, replacement, name)
        return name
    

    def to_check_url(self):
        result_urls = []
        ip_db = self.db
        ips = ip_db.view('ip')
        if ips:
            ips = [i[1] for i in ips]
            for ip in ips:
                # 构造json_link
                t = re.sub(r'\.\d+:', '##:', ip).split('##')
                urls = [t[0] + '.' + str(i) + t[1] + "/iptv/live/1000.json?key=txiptv" for i in range(1, 256)]
                result_urls += urls
            result_urls = list(set(result_urls))
            to_check_urls = [url for url in result_urls if 'http' or 'https' in url]
            return to_check_urls
        else: return []


    async def check_url(self, url, semaphore):
        try:
            async with semaphore:
                timeout = aiohttp.ClientTimeout(total=5)
                conn = aiohttp.TCPConnector(limit=100, ssl=False)
                async with aiohttp.ClientSession(connector= conn) as session:
                    async with session.get(url, timeout = timeout) as response:
                        if response.status == 200:
                            d = await response.text()
                            data = json.loads(d)['data']
                            names = [i['name'] for i in data]
                            names = [self.name_convert(name) for name in names]
                            channel_data  = list(zip(names, [url.split('/ip')[0] + i['url'] for i in data]))
                            
                            if channel_data:
                                print(f'{url} is valid, {len(channel_data)} channels found')
                                return channel_data
                            else: return []
        except Exception as e:
            # print(f"Error: {e}")
            return []
        

    def write_to_db(self, channel_data):
        # 写入数据库
        print(f'共获取{len(channel_data)}个频道')
        db_data = self.db.view('channel')
        db_data = [[i[1], i[2]] for i in db_data]
        new_data = [i for i in channel_data if i not in db_data]
        if new_data:
            print(f'有{len(new_data)}个新频道')
            print('开始写入数据库')
            self.db.delete('channel')
            for data in new_data:
                self.db.insert_channel(data[0], data[1])
            self.db.close()
        print(f'写入数据库完成，共写入{len(new_data)}个频道')

    async def start(self, semaphore=None):
        try:
            if semaphore:
                self.semaphore = asyncio.Semaphore(semaphore)
            to_check_urls = self.to_check_url()
            if to_check_urls:
                tasks = [asyncio.wait_for(self.check_url(url, self.semaphore), timeout=120) for url in to_check_urls]
                channel_data = await asyncio.gather(*tasks, return_exceptions=True)
                channel_data = [item for item in channel_data if item and not isinstance(item, Exception)]
                # print(channel_data)
                channel_datas = []
                for item in channel_data:
                    if item:
                        channel_datas += item
                print(f'{to_check_urls}个json_url检查完毕！')
                self.write_to_db(channel_datas)
                
        except Exception as e:
            print(f"Error: {e}")


if __name__ == '__main__':
    channel = CHANNEL()
    asyncio.run(channel.start())