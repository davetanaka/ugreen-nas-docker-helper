# よくある問題と解決法

> 私が実際にハマった問題と、どうやって解決したかの記録

## 🤔 まず確認すること

何か問題が起きたら、まずこれをチェック：

```bash
# 1. コンテナが動いているか確認
sudo docker ps

# 2. エラーログを見る
sudo docker logs コンテナ名
```

## 😅 よくハマる問題

### 1. コンテナが起動しない

**症状**: Portainerでコンテナが赤色（停止状態）

**私がやった解決方法**:
```bash
# まずログを確認
sudo docker logs duplicati
sudo docker logs jellyfin
sudo docker logs tailscale

# よくある原因：ポート競合
sudo netstat -tlnp | grep :8096
```

**解決策**: YAMLファイルでポート番号を変更
```yaml
ports:
  - 8097:8096  # 8096が使われてたら8097に変更
```

### 2. 「Permission denied」エラー

**症状**: ファイルにアクセスできない

**私の理解**: これが「理論と実践のギャップ」の典型例
- 設定: PUID=1000, PGID=100
- 実際: ファイルがdavetanakaやUID=911で作成される
- でも: なぜか動いてる（ことが多い）

**対処法**: 
1. **まず様子見**（多くの場合、実は問題ない）
2. **本当に問題があるなら権限修正**:
```bash
sudo chown -R 1000:100 /volume1/docker/configs/
```

### 3. 外付けHDDにアクセスできない

**症状**: Duplicatiで外付けHDDが見つからない

**確認方法**:
```bash
# 外付けHDDがマウントされているか確認
ls -la /mnt/@usb/
mount | grep usb
```

**私がやった解決法**:
```bash
# パスを確認して、YAMLファイルを修正
# 例：sdd1だと思ったらsda1だった
USB_PATH: /mnt/@usb/sda1  # 実際のパスに変更
```

### 4. Duplicatiでバックアップが外付けHDDに保存されない

**確認方法**:
```bash
# テストファイルで確認
sudo docker exec -it duplicati touch /backups/test.txt
ls -la /mnt/@usb/sdd1/duplicati-backups/
# test.txtが見えれば正常
```

**DuplicatiのWebUIで設定**:
- Storage Type: `Local folder or drive`
- Folder path: `/backups/duplicati-backups/`（重要：コンテナ内のパス）
- Source Data: `/source/volume1/`（これもコンテナ内のパス）

### 5. Tailscaleの認証ができない

**解決方法**:
```bash
# コンテナ内で認証コマンド実行
sudo docker exec -it tailscale tailscale up

# 表示されるURLをブラウザで開いて認証
```

### 6. JellyfinでメディアファイルHが見つからない

**確認方法**:
```bash
# コンテナ内でメディアフォルダを確認
sudo docker exec -it jellyfin ls -la /media/
```

**解決法**: YAMLでマウント設定を確認
```yaml
volumes:
  - /volume1:/media  # 全体をマウント
```

## 🔧 私のデバッグ方法

### ログを見る習慣
```bash
# 何か問題があったら、まずログ
sudo docker logs duplicati --tail 20
sudo docker logs jellyfin --tail 20
sudo docker logs tailscale --tail 20
```

### AI活用
私もよくChatGPTやClaudeに聞いています：

```
「UGREEN NASでDuplicatiを使っていますが、以下のエラーが出ています。
どうしたらいいでしょうか？

[エラーログをコピペ]」
```

### 諦めて再インストール
私の場合、Duplicatiは一度削除して再インストールしたら直りました。
変に設定をいじるより、最初からやり直す方が早いことも。

## 🆘 本当に困ったときは

1. **一旦全部停止**:
```bash
# Stackを停止
# Portainer → Stacks → 該当Stack → Stop
```

2. **環境検出スクリプト再実行**:
```bash
./ugreen-env-detect.sh
# 設定値に変化がないか確認
```

3. **YAMLファイル見直し**:
- IPアドレス
- パス設定
- ポート番号
- PUID/PGID

4. **それでもダメなら**: [GitHub Issues](https://github.com/davetanaka/ugreen-nas-docker-helper/issues)で質問してみてください

## 💡 予防策

### 定期的にやってること

**月1回**:
```bash
# システム更新
sudo apt update && sudo apt upgrade

# Dockerクリーンアップ
sudo docker system prune -f

# バックアップが正常に動いているか確認
# DuplicatiのWebUIで確認
```

**気づいたとき**:
- ディスク容量の確認: `df -h`
- メモリ使用量の確認: `free -h`

## 🤷‍♂️ 分からないことは分からない

正直、私もDockerの仕組みを完全に理解しているわけではありません。

- なぜPGIDが100で正解なのか？
- なぜdavetanakaユーザーでファイルが作成されるのか？
- なぜ設定が間違っていても動くのか？

こういう理屈は分からなくても、「実際に動く方法」を共有しています。

もっと詳しい方がいらっしゃったら、ぜひ教えてください！

---

> 「完璧を目指すより、まず動かすことから始めよう」
