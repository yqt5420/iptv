import asyncio
import aiohttp
import time
from db import Database
import pandas as pd
import json
import os
import random
import aiofiles
import shutil
from asyncio.subprocess import PIPE


class M3U8():
    def __init__(self):
        self.db = Database('ip.db')
        self.semaphore = asyncio.Semaphore(1024)

    async def ffm_video(self, file_path):
        cmd = f'ffprobe -i {file_path} -v quiet -print_format json -show_streams'
        args = cmd.split(' ')
        process = await asyncio.create_subprocess_exec(*args, stdout=PIPE)
        stdout = await process.stdout.read()
        # 返回json格式的视频信息
        video_info = json.loads(stdout)['streams']
        try:
            height = video_info[0]['height']
            return height
        except:
            return 0



    async def m_speed(self, session,ts_url):
        file_size = 0
        start_time = round(time.time())
        #测试m3u8速度

        f_path = 'tmp/' + str(random.randint(0, 1000000000)) + '.mp4'
        async with session.get(ts_url) as response:
            async with aiofiles.open(f_path, 'wb') as f:
                chunk = await response.content.read()
                await f.write(chunk)
                file_size += len(chunk)
        
        cost_time = round(time.time()) - start_time
        speed = round(file_size / cost_time / 1024, 2) 
        height = await self.ffm_video(f_path)
        return speed, height
    
    async def speed(self, session,ts_url):
        file_size = 0
        start_time = round(time.time())
        #测试m3u8速度
        async with session.get(ts_url) as response:
            while True:
                chunk = await response.content.read(1024 * 1024 * 1024 * 5)  # 读取二进制数据 10mb
                if not chunk:
                    break
                file_size += len(chunk)
        cost_time = round(time.time()) - start_time
        speed = round(file_size / cost_time / 1024, 2)
        return speed


    async def testm3u(self, data, semaphore, dp=False):
        '''
        输入m3u8源链接，返回速度
        :param url: m3u8文件链接
        :param semaphore: 并行数'''
        try:
            url = data[1]
            name = data[0]
            async with semaphore:
                conn = aiohttp.TCPConnector(limit=100, ssl=False)
                async with aiohttp.ClientSession(connector= conn) as session:
                    async with session.get(url) as response:
                        channel_url_t = url.rstrip(url.split('/')[-1])  # m3u8链接前缀
                        res = await response.text()
                        lines = res.strip().split('\n')  # 获取m3u8文件内容
                        ts_lists = [line.split('/')[-1] for line in lines if line.startswith('#') == False]  # 获取m3u8文件下视频流后缀
                        ts_url = channel_url_t + ts_lists[0]
                    
                    # 获取视频分辨率
                    if dp:
                        speed, height = await self.m_speed(session, ts_url) 
                    else:
                        speed = await self.speed(session, ts_url)
                        height = 0
                    # self.delete_file(f_path)
                    if speed > 10:
                        print(f"正在测试{url}\n下载速度为：{speed} KB/s")
                        return (name, url, speed, height)
                    else:
                        return 0
        except Exception as e:
            # print(f"Error: {e}")
            return 0
    

    def get_data(self):
        datas = self.db.view('channel')
        datas = [[item[1], item[2]] for item in datas] 
        self.db.close()
        print(f'共 {len(datas)} 个频道待测试')
        return datas


    def write_data(self, results, fpath):
        df = pd.DataFrame(results, columns=['A', 'B', 'C', 'D'])
        # 按照第一项进行分组，选出每组中第三项最大的元组,网速最快的
        print(f'开始去重，{len(results)}个频道')
        result = df.loc[df.groupby('A')['C'].idxmax()]
        result = df.loc[df.groupby('A')['D'].idxmax()]

        # 按照'A'项从小到大进行排序
        result_sorted = result.sort_values(by='A', ascending=True)
        #转换成列表元组
        result_sorted_list = result_sorted.values.tolist()
        with open(fpath, 'w', encoding='utf-8') as f:
            f.write('#EXTM3U x-tvg-url="http://epg.51zmt.top:8000/e.xml.gz"\n')
            for i in result_sorted_list:
                f.write('#EXTINF:-1 tvg-name="{}",{}\n{}\n'.format(i[0], i[0], i[1]))
        print(f'去重完毕，共{len(result_sorted_list)}个可用频道, 写入成功!')



    async def start(self, fpath, semaphore=None, dp=False):
        # 自定义并发数 默认1024
        try:
            if semaphore:
                self.semaphore = asyncio.Semaphore(semaphore)
            datas = self.get_data()
            if datas:
                os.makedirs('tmp', exist_ok=True)
                tasks = [asyncio.wait_for(self.testm3u(data, self.semaphore, dp), timeout=6000) for data in datas]
                results = await asyncio.gather(*tasks, return_exceptions=True)
                results = [result for result in results if result and not isinstance(result, Exception)]
                self.write_data(results, fpath)
                shutil.rmtree('tmp', ignore_errors=True)
                return results
            else:
                print('数据库中无可用频道，请更新！')
            
        except Exception as e:
            print(f"Error: {e}")
            return 0
        

if __name__ == '__main__':
    m3u8 = M3U8()
    fpath = 'm3u8.m3u'
    results = asyncio.run(m3u8.start(fpath, 2048))
    
