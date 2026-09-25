# BoltSnip 授权说明

授权版提供两种入口：离线授权文件供作者自己使用，客户码由联网服务绑定一台 Windows 安装。客户在新电脑输入原激活码后，绑定自动转移，旧电脑在下一次联网校验时失效。授权保护普通分发场景；拥有并修改客户端二进制文件的人仍可能绕过本地检查。

托盘菜单的“授权管理…”可查看当前授权、更换授权或取消此电脑的授权。取消时，本机保存的 `owner.license` 和 `customer.key` 会移到 `%LOCALAPPDATA%\BoltSnip\revoked\` 下的新备份目录，截图立即停止，直到重新激活。此操作不解除联网激活码在服务端的设备绑定；原码仍可在本机或新电脑重新激活。

## 作者的离线授权

只需生成一次签名密钥和授权文件。默认私钥保存在 `D:\Codex\Work\BoltSnip\owner-private.xml`，用 Windows 当前用户的 DPAPI 加密；公钥保存在仓库的 `licensing\owner-public.xml`。私钥文件不要提交到 Git，也不要和授权文件一起发给客户。

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\owner-license.ps1 -Action init
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\tools\owner-license.ps1 -Action issue
```

授权文件默认生成在 `D:\Codex\Outputs\BoltSnip-owner.license`。在授权版 BoltSnip 中选择“导入离线授权”，换机时复制同一个文件即可。文件不绑定电脑，泄露后别人也能导入。DPAPI 私钥只能由原 Windows 用户解密；单独复制加密私钥文件到新系统，通常无法恢复签发能力。请妥善保留现有授权文件。已有私钥时不要再运行 `init`。

## 客户激活服务

服务只需要 Python 标准库和 SQLite，不需要管理网页。数据库默认建议放在 D 盘，服务仅监听本机，由 HTTPS 反向代理对外提供访问。

```powershell
python .\licensing\server.py --db D:\Codex\Work\BoltSnip\licenses.db create
python .\licensing\server.py --db D:\Codex\Work\BoltSnip\licenses.db serve
```

`create` 会打印一个客户码。客户输入后，该码绑定当前 Windows 安装。换机时在新电脑输入同一码即可自动转移绑定，无需管理员操作。持有码的人也能执行转移，因此客户码应妥善保管。

如需主动清除某个码的当前绑定，管理员仍可运行 `release` 命令并按提示输入该码。

服务提供 `POST /activate` 和 `POST /check`。正式部署必须通过 HTTPS 暴露，反向代理应只把这两个路径转发到本机 `127.0.0.1:8765`。不要把服务的明文 HTTP 端口直接暴露到公网。客户启动时校验，运行期间每分钟复核；旧电脑最多到下一次校验才会失效。连不上服务时，后续截图会暂停，恢复连通后会重新放行。没有配置断网宽限期。

设备绑定使用 Windows `MachineGuid` 的哈希。重装系统或系统镜像克隆可能改变或复制它；重新输入原码即可转移。客户端设备信息可被有意伪造，因此这不是防破解机制。

需要本机测试时，使用上面的命令启动服务，再构建指向本机服务的测试安装包：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1 -OutputDirectory .\dist\license-test -OwnerPublicKeyPath .\licensing\owner-public.xml -LicenseServerUrl http://127.0.0.1:8765
```

这个测试安装包只适用于运行服务的同一台电脑。正式安装包应使用已部署的 HTTPS 激活服务地址。

## 小型 NAT VPS

服务端只需复制 `bsoio` 和 `licensing/server.py`，保持两者的相对位置。它们使用 Python 标准库与一个 SQLite 文件，不需要 Docker、MySQL 或后台管理网页。在 Linux 上先建立仅管理员可读的数据目录，并把 `bsoio` 加入命令搜索路径：

```sh
mkdir -m 700 -p ~/boltsnip
chmod +x ./bsoio
sudo ln -s "$(pwd)/bsoio" /usr/local/bin/bsoio
bsoio c
bsoio d MyLicense
bsoio
bsoio s
```

`bsoio` 会列出所有客户码及其绑定状态、设备标识、创建时间、最近校验时间和换机次数；`bsoio c` 每次生成一个新的随机 `BS-` 客户码。`bsoio d MyLicense` 会直接创建完整激活码 `MyLicense`，不会加前缀或随机尾码；只输入 `bsoio d` 时会提示输入。自定义码只允许 1–128 个英文字母（A–Z、a–z），区分大小写，不允许重复。短码容易被猜到，建议自定义码写长一些。`bsoio s` 会启动一个持续运行的激活服务，接收客户软件发来的激活和校验请求；在终端里运行时会一直占用这个终端，按 Ctrl+C 可以停止。默认数据库为当前用户的 `~/boltsnip/licenses.db`，也可在发码和运行服务时统一设置 `BOLTSNIP_DB` 为一个绝对路径。运行 `bsoio s` 的用户必须能访问同一个数据库。

为支持随时列出完整客户码，新码会以原文保存在数据库中；数据库文件在 Linux 上新建时设为仅当前用户可读写。旧版数据库会自动添加新字段，但旧码原文无法从哈希恢复，只能显示哈希摘要。不要把数据库文件发给客户，并定期备份。服务默认只监听 `127.0.0.1:8765`，不能直接供公网客户访问。

传统 NAT 映射部署需要把域名、HTTPS 和映射端口接到反向代理，再由代理转发到 `127.0.0.1:8765`。如果公网只分配了非 443 端口，安装包的 `-LicenseServerUrl` 必须写成 `https://bs.oioio.cyou:映射端口`。若 80/443 无法映射，普通 HTTP/TLS 端口验证不适用；证书需要通过 DNS 验证等方式取得。下面的 Cloudflare Tunnel 方案不需要这些入站端口，也不需要把域名解析到 NAT VPS 的公网地址。

### Alpine + Cloudflare DNS

如果 `oioio.cyou` 已接入 Cloudflare DNS，最短路径是 Cloudflare Tunnel：Tunnel 在 VPS 上主动连接 Cloudflare，不需要 NAT 入站映射。仓库里的 `deploy/alpine/install.sh` 会安装 Python、复制激活服务文件、配置 OpenRC 并启动服务。**先把这些文件推送到仓库**。下面按 root 登录 Alpine 说明；如果 SSH 登录的是其他用户，先进入 root shell。公开仓库可直接运行：

```sh
apk add --no-cache git
git clone --depth 1 https://github.com/VAR7IANT/BoltSnip.git /opt/boltsnip-src
sh /opt/boltsnip-src/deploy/alpine/install.sh
bsoio c
bsoio
```

如果仓库是私有的，先在 VPS 配置只读 GitHub deploy key，再把上面的 clone 地址换成 SSH 地址。更新服务时运行：

```sh
git -C /opt/boltsnip-src pull --ff-only
sh /opt/boltsnip-src/deploy/alpine/install.sh
rc-service bsoio status
```

数据库保存在 VPS 的 `/root/boltsnip/licenses.db`，不在 Git 仓库内，更新不会覆盖它。Cloudflare Tunnel 只需首次配置：从 [Cloudflare 官方下载页](https://developers.cloudflare.com/tunnel/downloads/)安装与 VPS 架构对应的 `cloudflared` Linux 二进制，然后运行 `cloudflared --version` 确认。Cloudflare 控制台进入 **Networking → Tunnels**，创建 Tunnel；在 VPS 上执行控制台给出的 `cloudflared service install` 命令（命令中包含 token），再执行 `rc-update add cloudflared default`、`rc-service cloudflared start`。在这个 Tunnel 的 **Routes** 中添加 **Published application**：hostname 为 `bs.oioio.cyou`，service URL 为 `http://127.0.0.1:8765`。不要给该路由加交互式 Access 登录，否则客户端无法自动校验。Token 是管理凭据，不要发给客户。

用 `curl -fsS -X POST https://bs.oioio.cyou/check -d 'key=invalid&device=x'` 检查连通；返回 `INVALID` 表示公网请求已到达激活服务。随后用本机 Windows 构建指向 `https://bs.oioio.cyou` 的安装包。`bsoio` 默认数据库是运行它的用户的 `~/boltsnip/licenses.db`，以上步骤统一由 root 运行，发码与 OpenRC 使用同一个数据库。后续请备份这个数据库。

## 构建授权版

确定服务的 HTTPS 地址后，运行：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\build-installer.ps1 -OwnerPublicKeyPath .\licensing\owner-public.xml -LicenseServerUrl https://bs.oioio.cyou
```

开发时可以把服务地址设为 `http://127.0.0.1:8765` 并用 `build.ps1 -EnableLicensing` 构建测试版。普通 `build.ps1` 默认构建不带授权门禁的开发版；正式安装包脚本会强制启用授权。服务地址写进 EXE，变更地址需要重新构建。
