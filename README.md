# jds-pro-deploy

echo "# jds-pro-deploy" >> README.md
git init
git add README.md
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/BIDXOM/jds-pro-deploy.git
git push -u origin main

git remote add origin https://github.com/BIDXOM/jds-pro-deploy.git
git branch -M main
git push -u origin main



溫馨提示：如何一次性把首版代码推入裸仓（走本机文件路径）
1.	看一下你当前的远程地址：
 git remote -v

2.	把 origin 改为本机裸仓路径（可写）：
git remote set-url origin /opt/git/oneclick-deploy.git
# 或者新增一个专用于写入的远程名
# git remote add publish /opt/git/oneclick-deploy.git

3.	推送（你当前分支是 master）：
git push origin master
# 如果你用了上面的 publish 名：
# git push publish master

4.	验证裸仓里已有提交：
cd /opt/git/oneclick-deploy.git
git log --oneline --decorate --graph --all | head

5)（可选）确保只读导出开启（给 git-daemon 用）：
touch /opt/git/oneclick-deploy.git/git-daemon-export-ok

之后，其他电脑克隆用只读地址即可：
git clone git://<服务器IP>:9418/oneclick-deploy.git

