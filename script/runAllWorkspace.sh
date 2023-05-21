#!/bin/bash

# コマンド1をバックグラウンドで実行
pnpm dev &
pid1=$!

# コマンド2をバックグラウンドで実行
cd submodules/misskey-v13/packages/frontend
pnpm dev &
pid2=$!

# Ctrl+C を捕捉して両方のコマンドを終了
trap 'kill $pid1; kill $pid2; exit' INT

# ここで何か別の処理を行う場合は追加

# 両方のコマンドが終了するまで待つ
wait $pid1
wait $pid2
