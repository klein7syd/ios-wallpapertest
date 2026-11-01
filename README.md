# Todo Wallpaper
原生iOS待办、壁纸、小组件与连心；iOS17+，无第三方库。
Windows解压安装包后连接iPhone，运行Install-TodoWallpaper.cmd；同账号覆盖安装，不先卸载。
连心已移除“先体验”入口；旧示例内容仍兼容读取及分享标注，Mock仅保留协议检查使用。
后台将家常提示词转为自然回应，整批少量称呼，默认不在台词中写成员名/团名，不硬塞TMI。
生成时用名字/团体查询维基百科及K-pop Wiki公开接口；结果有来源链接，不能当身份核验。
只提炼公开形象与语气，排除私人信息；找不到或网络不通时降级，不编造查阅结果；其他大吧未接入。
Wiki查询不带密钥、称呼、提示词或照片；摘要只进App私有资料和用户AI请求，不进小组件共享文件。
连心小组件→内容→显示几句：全部/1–8句；与生成数量独立保存，默认全部，空间不足显示能放下的前几句。
“句数/重新生成/底图”的整块外层底板使用26pt连续圆角并实际裁切，不只是内部按钮变圆。
密钥仅在本机钥匙串，AI只接HTTPS；照片不发AI；共享数据不含凭证、接口、提示词及角色资料。
接口核实2026-11-01：[MediaWiki搜索](https://www.mediawiki.org/wiki/API:Search)、[摘要](https://www.mediawiki.org/wiki/Extension:TextExtracts)、[Fandom公开API](https://dev.fandom.com/wiki/Dev_Wiki:Sandbox/API)；本轮未改服务商接口。
本轮没有新增界面检查、放宽门禁或修改受保护源码哈希。
默认只交付Windows安装zip和15行内说明；不自动产出审阅/快照/Evidence、不更新交接文档或运行handoff。
本地编译优先；完整CI一次、失败最多重试两次；真机点击、系统刷新及真实AI效果仍需设备验证。
