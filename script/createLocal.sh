#!/bin/bash

# 入力ディレクトリのパス
input_dir=misskeyV13/locales

# 出力ディレクトリのパス
output_dir=src/locales

# YAML ファイルを処理するループ
find "${input_dir}" -name "*.yml" -type f | while read file; do
    # 出力ファイルのパスを作成
    output_file="${output_dir}/$(basename "${file}" .yml).json"

    # Backspace制御文字を削除
    sed -i '' 's/\x08//g' "${file}"

    # YAML を JSON に変換し、整形して出力
    yq eval -o=json "${file}" | jq '.' > "${output_file}"
done


# ja.json
mv src/locales/ja-JP.json src/locales/ja-JP.tmp.json
mv src/locales/ja-KS.json src/locales/ja-KS.tmp.json
jq -s '.[0] * .[1]' RiricaSrc/locales/ja.json src/locales/ja-JP.tmp.json > src/locales/ja-JP.json
jq -s '.[0] * .[1]' RiricaSrc/locales/ja.json src/locales/ja-KS.tmp.json > src/locales/ja-KS.json

# kr.json
mv src/locales/ko-KR.json src/locales/ko-KR.tmp.json
jq -s '.[0] * .[1]' RiricaSrc/locales/ko.json  src/locales/ko-KR.tmp.json > src/locales/ko-KR.json

rm src/locales/*.tmp.json

# en.jsonをsrc/locals以下のすべてのjsonにマージする
for file in src/locales/*.json; do
    if [ "$file" = "src/locales/ja-JP.json" ] || [ "$file" = "src/locales/ja-KS.json" ] || [ "$file" = "src/locales/ko-KR.json" ]; then
      echo "skiped"
        continue # 条件に一致したらループをスキップする
    fi

    echo $file
    jq -s '.[0] * .[1]' "$file" RiricaSrc/locales/en.json > "$file.tmp"
    mv "$file.tmp" "$file"
done