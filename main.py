import asyncio
from module.m3u8 import M3U8
from module.ip import IP
from module.channel import CHANNEL
from module.git import push_to_git
from module.server import run as server
import schedule
import time


def m3u():

    m3u = M3U8()
    fpath = 'iptv.m3u'
    asyncio.run(m3u.start(fpath, 2048))
    # push_to_git()


def update_ip():
    ip = IP()
    asyncio.run(ip.update())


def update_channel():
    channel = CHANNEL()
    asyncio.run(channel.start())




def main():
    # 每天8点更新m3u8
    schedule.every().day.at("04:00").do(m3u)
    # 每周一执行一次更新ip
    schedule.every().monday.do(update_ip) 
    schedule.every().day.at("05:00").do(update_channel)
    while True:
        schedule.run_pending()
        time.sleep(1)

def main_menu():
    while True:
        print("\n欢迎使用组播iptv扫描系统！请选择一个操作：")
        print("1. 更新m3u8文件")
        print("2. 更新频道数据库")
        print("3. 更新源IP")
        print("4. 启动定时任务")
        print("5. 退出")

        try:
            choice = int(input("请输入选项（1-4）："))
        except ValueError:
            print("请输入有效的数字选项。")
            continue

        if choice == 1:
            m3u()
            break
        elif choice == 2:
            update_channel()
            break
        elif choice == 3:
            update_ip()
            break
        elif choice == 4:
            main()
            break
        elif choice == 5:
            print("退出程序。")
            break
        else:
            print("选项无效，请输入1-4之间的数字。")




if __name__ == '__main__':
    main_menu()


