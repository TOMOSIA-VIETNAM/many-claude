<h1 align="center">
  <img src="assets/logo.svg" alt="mclaude" width="480">
</h1>

<h3 align="center">Mỗi dự án một account Claude Code.<br>Tự đổi account khi bạn <code>cd</code>.</h3>

<p align="center">
  <code>mclaude add</code> · <code>mclaude bind</code> · <code>mclaude which</code>
</p>

<p align="center">
  <a href="https://github.com/TOMOSIA-VIETNAM/mclaude/actions/workflows/test.yml"><img alt="test" src="https://github.com/TOMOSIA-VIETNAM/mclaude/actions/workflows/test.yml/badge.svg?branch=master"></a>
  <a href="LICENSE"><img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="macOS" src="https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white">
  <img alt="zsh" src="https://img.shields.io/badge/shell-zsh-4EAA25?logo=gnubash&logoColor=white">
  <img alt="Claude Code" src="https://img.shields.io/badge/Claude%20Code-supported-D97757?logo=claude&logoColor=white">
</p>

<p align="center"><a href="README.md">English</a> · Tiếng Việt</p>

`mclaude` giúp bạn dùng nhiều account Claude Code (subscription) trên cùng một máy. Mỗi dự án được gắn với một account; khi bạn `cd` vào thư mục dự án và gõ `claude`, account tương ứng sẽ tự động được dùng.

- Không ghi bất kỳ file nào vào thư mục dự án — không lo commit nhầm.
- Settings, skills, plugins, hooks, `CLAUDE.md` dùng chung giữa các account.
- Chỉ dành cho Claude Code CLI trên zsh (macOS).

Lệnh điều khiển là `mclaude`. Đây là shell function do tool này định nghĩa (không phải lệnh có sẵn của hệ thống hay của Claude Code), được nạp vào zsh khi cài đặt.

## Cách hoạt động

Claude Code đọc biến môi trường `CLAUDE_CONFIG_DIR` để biết thư mục config (gồm phiên đăng nhập, history, memory). Tool tạo cho mỗi account một thư mục config riêng, và bọc lệnh `claude` bằng một shell function:

1. Lấy thư mục hiện tại (`$PWD`).
2. Tra trong file map `~/.mclaude/projects.conf`, chọn dòng có đường dẫn khớp **dài nhất** (thư mục con kế thừa profile của thư mục cha).
3. Đặt `CLAUDE_CONFIG_DIR=~/.mclaude/profiles/<profile>` rồi chạy Claude Code thật.
4. Nếu không khớp dòng nào → dùng `~/.claude` như bình thường (profile `default`).

```
~/.claude/                         # profile "default" + nguồn config dùng chung (không bị tool sửa)
~/.mclaude/                    # mọi thứ của tool nằm ở đây
├── mclaude.zsh                    # script, được source từ ~/.zshrc
├── projects.conf                  # map: đường dẫn → profile
└── profiles/
    ├── client-x/                  # account B
    │   ├── settings.json -> ~/.claude/settings.json
    │   ├── skills        -> ~/.claude/skills
    │   ├── ...                    # các symlink dùng chung khác
    │   ├── .claude.json           # riêng: thông tin account, onboarding
    │   └── projects/              # riêng: memory, history
    └── client-y/                  # account C
```

## Cài đặt

Một lệnh:

```zsh
./install.sh && source ~/.zshrc
```

`install.sh` sẽ:
- Tạo `~/.mclaude/` (gồm `profiles/` và `projects.conf`) và **copy** `mclaude.zsh` vào đó — cài xong có thể xoá thư mục repo.
- Thêm một dòng `source ~/.mclaude/mclaude.zsh` vào cuối `~/.zshrc` (chỉ thêm một lần).
- Nâng cấp từ tên cũ `many-claude`: chuyển `~/.many-claude` (profile, binding) sang `~/.mclaude` và thay dòng cũ trong `~/.zshrc`. Sau đó kiểm tra `mclaude status <profile>`; nếu profile báo chưa đăng nhập thì login lại.
- Dọn layout cũ `~/.config/claude-switch` nếu có.

Chạy lại `install.sh` bất cứ lúc nào để cập nhật script; profile và binding được giữ nguyên.

`source ~/.zshrc` nạp `mclaude` vào terminal hiện tại; terminal mở sau sẽ tự có.

Kiểm tra:

```zsh
mclaude list
mclaude which
```

## Bắt đầu nhanh

Ví dụ: gắn account công ty B cho mọi dự án trong `~/Project/ClientX`.

```zsh
mclaude add client-x                          # 1. tạo profile
mclaude login client-x                        # 2. đăng nhập account B (mở browser)
mclaude bind client-x ~/Project/ClientX       # 3. gắn thư mục với profile

cd ~/Project/ClientX/api
claude                                    # → chạy với account B
```

Kiểm tra account đang dùng:

```zsh
cd ~/Project/ClientX && mclaude status        # account B
mclaude status default                        # account gốc, không bị ảnh hưởng
```

## Các lệnh

| Lệnh | Mô tả |
|---|---|
| `mclaude` / `mclaude which` | In profile và thư mục config áp dụng cho thư mục hiện tại |
| `mclaude list` | Liệt kê các profile và toàn bộ binding |
| `mclaude add <profile>` | Tạo profile mới trong `~/.mclaude/profiles/<profile>` và tạo symlink config dùng chung |
| `mclaude login [profile]` | Đăng nhập cho profile (mặc định: profile của thư mục hiện tại) |
| `mclaude logout [profile]` | Đăng xuất profile |
| `mclaude status [profile]` | Xem trạng thái đăng nhập của profile |
| `mclaude bind <profile> [path]` | Gắn thư mục với profile (mặc định: thư mục hiện tại). Bind lại cùng thư mục sẽ ghi đè, không tạo dòng trùng |
| `mclaude unbind [path]` | Bỏ gắn thư mục (mặc định: thư mục hiện tại) |
| `mclaude help` | Hiện hướng dẫn sử dụng |
| `claude ...` | Chạy Claude Code với profile của thư mục hiện tại; mọi tham số được chuyển tiếp nguyên vẹn |

Tên `default` được dành riêng cho `~/.claude`.

## File map `projects.conf`

Mỗi dòng: `<đường dẫn> <profile>`. Profile là từ cuối cùng, nên đường dẫn được phép chứa dấu cách. Dòng bắt đầu bằng `#` là comment. Có thể dùng `~`.

```
# ~/.mclaude/projects.conf
/Users/admin/Project/ClientX            client-x
/Users/admin/Project/ClientX/legacy     client-y
~/Project/My Side Project               personal
```

Với ví dụ trên:

| Thư mục hiện tại | Profile |
|---|---|
| `~/Project/ClientX/api` | `client-x` |
| `~/Project/ClientX/legacy/web` | `client-y` (khớp dài hơn) |
| `~/Project/My Side Project` | `personal` |
| `~/Downloads` | `default` |

Bạn có thể sửa file này bằng tay hoặc dùng `mclaude bind` / `mclaude unbind`. Đường dẫn đi qua symlink được resolve về đường dẫn thật trước khi so khớp.

## Config dùng chung

Khi tạo profile (và mỗi lần chạy `claude` với profile đó), các mục sau trong `~/.claude` được symlink sang profile nếu tồn tại:

```
settings.json  CLAUDE.md  keybindings.json  skills  plugins  hooks
agents  commands  output-styles  statusline.sh
```

Sửa ở `~/.claude` là mọi profile cùng nhận. Muốn chia sẻ thêm mục khác, thêm vào mảng `MCLAUDE_SHARED` trong `mclaude.zsh`. Muốn một profile dùng config riêng cho một mục, xoá symlink trong thư mục profile và đặt file thật vào đó — `mclaude` không ghi đè file đã có.

**Không dùng chung** (riêng từng profile): phiên đăng nhập, `.claude.json` (thông tin account, MCP server cấp user), `projects/` (memory, history theo dự án).

## Biến môi trường tuỳ chỉnh

Đặt trước dòng `source` trong `~/.zshrc` nếu muốn đổi vị trí mặc định:

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `MCLAUDE_HOME` | `~/.mclaude` | Nơi chứa `projects.conf` |
| `MCLAUDE_PROFILES` | `$MCLAUDE_HOME/profiles` | Nơi chứa thư mục các profile |
| `MCLAUDE_BASE` | `~/.claude` | Profile `default` và nguồn config dùng chung |

## Lưu ý

- **Không đổi account giữa session.** Profile được chọn lúc chạy `claude`. Đang trong session mà chuyển dự án thì cần thoát và chạy lại.
- **Override thủ công:** nếu `CLAUDE_CONFIG_DIR` đã được đặt sẵn trong môi trường, wrapper tôn trọng giá trị đó và không tra map. Ví dụ chạy tạm một account khác: `CLAUDE_CONFIG_DIR=~/.mclaude/profiles/client-y claude`.
- **MCP server cấp user** nằm trong `.claude.json` của từng profile, nên cần thêm lại cho mỗi profile (`claude mcp add --scope user ...`).
- **Chỉ CLI zsh.** Extension VS Code/JetBrains, script dùng `sh`/`bash`, hoặc gọi trực tiếp binary (`command claude`, `~/.local/bin/claude`) sẽ không đi qua wrapper.
- **Keychain macOS:** mỗi profile giữ phiên đăng nhập subscription riêng trong Keychain, đăng nhập profile này không thay thế profile khác (đã thử với account thật).
- Nếu `mclaude login` không chạy được với phiên bản Claude Code của bạn, vào thư mục dự án, chạy `claude` rồi gõ `/login`.

## Chạy test

```zsh
zsh tests/test.zsh
```

Không cần cài thêm gì. Mỗi test chạy trong HOME tạm với một `claude` giả, nên không đụng tới `~/.claude`, `~/.mclaude` hay `~/.zshrc` thật. Test bao phủ: chọn profile theo thư mục (thư mục con, khớp dài nhất, thư mục anh em, dấu cách, symlink, `~`, comment), override bằng `CLAUDE_CONFIG_DIR`, tạo profile và symlink config dùng chung, `bind`/`unbind`/`list`/`which`/`help`, `login`/`logout`/`status`, chịu được option shell của người dùng, `install.sh` (cài mới, chạy lại, chuyển layout cũ) và `uninstall.sh` (giữ hoặc xoá profile, kể cả câu hỏi tương tác).

Đăng nhập thật và việc tách Keychain không có test tự động; đã được kiểm tra thủ công với account thật.

## Gỡ cài đặt

Một lệnh:

```zsh
./uninstall.sh
```

- Xoá dòng `source` trong `~/.zshrc`.
- Nếu có profile, script hỏi có xoá không (mặc định **không**):
  - Trả lời `N`: chỉ gỡ `mclaude.zsh` và `projects.conf`, giữ lại `~/.mclaude/profiles/` — cài lại sau sẽ dùng tiếp được.
  - Trả lời `y`: đăng xuất từng profile rồi xoá toàn bộ `~/.mclaude`. **Thao tác này xoá vĩnh viễn phiên đăng nhập, memory và history của các account đó.**
- Gỡ sạch không cần hỏi (dùng cho script): `./uninstall.sh --purge`.

`~/.claude` (profile `default`) không bao giờ bị động tới. Sau khi gỡ, mở terminal mới (hoặc `exec zsh`) để shell hiện tại không còn lệnh `mclaude`.

## License

[MIT](LICENSE)
