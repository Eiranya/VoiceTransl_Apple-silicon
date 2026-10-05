这个文件夹需要存在。

打包时 translate.spec 的产物会替换本目录内容，app.py 以 `translate/translate` 启动翻译子进程。
若本目录缺失，app-macos.spec 会因 datas 找不到 `translate/` 而打包失败。
