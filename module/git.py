import subprocess

def run_git_command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
    print(result.stdout)

def push_to_git():
    try:
        # 假设当前目录已经是Git仓库
        run_git_command(["git", "config", "--global", "user.name", "yqt5420"])
        run_git_command(["git", "config", "--global", "user.email", "yqt5420@gmail.com"])
        run_git_command(["git", "add", "."])
        run_git_command(["git", "commit", "-m", "Your commit message"])
        run_git_command(["git", "push", "-f", "origin", "master"])
        print("代码已成功推送到远程仓库。")
    except subprocess.CalledProcessError as e:
        print("推送过程中发生错误：", e.stderr)

if __name__ == "__main__":
    push_to_git()