# jds-pro-deploy

溫馨提示：如何一次性把首版代码推入裸仓（走本机文件路径）

1、在同一服务器中，同步裸仓代码：

仓库根： /opt/git
服务URL 例： git://<服务器IP>:9413/<repo>.git
克隆示例： git clone git://<服务器IP>:9413/Test.git

#echo "# jds-pro-deploy" >> README.md
#git add README.md
#git commit -m "first commit"

中Test中新增代码，提交后，暂不推送，执行下面步骤

2.	看一下你当前的远程地址：
#git remote -v

3、把 origin 改为本机裸仓路径（可写）：
git remote set-url origin /opt/git/Test.git
# 或者新增一个专用于写入的远程名
# git remote add publish /opt/git/Test.git


4.	推送（你当前分支是 master）：
git push origin master
# 如果你用了上面的 publish 名：
# git push publish master


5.	验证裸仓里已有提交：
#cd /opt/git/oneclick-deploy.git
#git log --oneline --decorate --graph --all | head

6.（可选）确保只读导出开启（给 git-daemon 用）：
#touch /opt/git/Test.git/git-daemon-export-ok

之后，其他电脑克隆用只读地址即可：
#git clone git://<服务器IP>:9413/Test.git
